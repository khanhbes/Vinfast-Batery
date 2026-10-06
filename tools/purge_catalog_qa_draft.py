"""Delete only an unpublished, unreferenced QA draft; retain audit evidence."""
import argparse
import json
import logging
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--credential-file', required=True)
    parser.add_argument('--catalog-id', required=True)
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    if not args.catalog_id.startswith('qa-agent-20261006-') or '/' in args.catalog_id:
        raise ValueError('notQaCatalogId')
    logging.disable(logging.CRITICAL)
    import firebase_admin
    from firebase_admin import credentials, firestore
    credential = credentials.Certificate(args.credential_file)
    if credential.project_id != 'vinfast-873db':
        raise ValueError('unexpectedProject')
    firebase_admin.initialize_app(credential)
    db = firestore.client()
    ref = db.collection('VehicleCatalogDrafts').document(args.catalog_id)
    if db.collection('VehicleCatalog').document(args.catalog_id).get().exists:
        raise ValueError('publishedRecordPresent')
    from google.cloud.firestore_v1.base_query import FieldFilter
    for field in ('catalogId', 'vehicleCatalogId', 'modelId'):
        if list(db.collection('Vehicles').where(filter=FieldFilter(field, '==', args.catalog_id)).limit(1).stream()):
            raise ValueError('vehicleReferencePresent')
    snapshot = ref.get()
    if not snapshot.exists:
        print(json.dumps({'qaDraftAbsent': True, 'deleted': False}))
        return 0
    def valid(data):
        return (data.get('status') == 'draft' and data.get('brandName') == 'QA Agent 20261006'
                and data.get('brandId') == 'qa-agent-20261006'
                and str(data.get('model', '')).startswith('QA Runtime ')
                and data.get('revision', 0) == 0)
    if not valid(snapshot.to_dict() or {}):
        raise ValueError('qaMarkerMismatch')
    if not args.execute:
        print(json.dumps({'dryRun': True, 'guardPassed': True}))
        return 0
    @firestore.transactional
    def delete(transaction):
        current = ref.get(transaction=transaction)
        published = db.collection('VehicleCatalog').document(args.catalog_id).get(transaction=transaction)
        if published.exists or not current.exists or not valid(current.to_dict() or {}):
            raise ValueError('qaRecordChanged')
        transaction.delete(ref)
    delete(db.transaction())
    absent = not ref.get().exists
    print(json.dumps({'deleted': True, 'qaDraftAbsent': absent, 'auditRetained': True}))
    return 0 if absent else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(json.dumps({'pass': False, 'failureType': type(error).__name__}))
        sys.exit(1)
