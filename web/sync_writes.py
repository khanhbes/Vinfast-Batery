"""Ownership checks and writes share one Firestore transaction.

All reads happen before writes; a conflicting owner rejects the entire batch.
"""
def valid_document_id(value):
    return isinstance(value, str) and bool(value.strip()) and value not in ('.', '..') and '/' not in value and len(value.encode('utf-8')) <= 1500


def commit_owned_writes(db, writes, uid, runner=None):
    if len(writes) > 400:
        raise ValueError('Mỗi lần đồng bộ tối đa 400 bản ghi')
    targets = {}
    vehicle_ids = set()
    for collection, doc_id, data in writes:
        if not valid_document_id(doc_id):
            raise ValueError('Mã bản ghi không hợp lệ')
        key = (collection, doc_id)
        if key in targets:
            raise ValueError('Mã bản ghi bị trùng trong cùng yêu cầu')
        targets[key] = (db.collection(collection).document(doc_id), data)
        vehicle_id = data.get('vehicleId')
        if collection != 'Vehicles' and vehicle_id:
            if not valid_document_id(vehicle_id):
                raise ValueError('vehicleId không hợp lệ')
            vehicle_ids.add(vehicle_id)

    def operation(transaction):
        for (collection, doc_id), (ref, _) in targets.items():
            snapshot = ref.get(transaction=transaction)
            if snapshot.exists and (snapshot.to_dict() or {}).get('ownerUid') != uid:
                # Legacy user profiles are inherently scoped by their document ID.
                if not (collection == 'users' and doc_id == uid and not (snapshot.to_dict() or {}).get('ownerUid')):
                    raise PermissionError('Không có quyền đồng bộ bản ghi này')
        for vehicle_id in vehicle_ids:
            if ('Vehicles', vehicle_id) in targets:
                continue  # Ownership of this target was checked above.
            vehicle = db.collection('Vehicles').document(vehicle_id).get(transaction=transaction)
            if not vehicle.exists or (vehicle.to_dict() or {}).get('ownerUid') != uid:
                raise PermissionError('Xe không thuộc tài khoản đang đăng nhập')
        for ref, data in targets.values():
            transaction.set(ref, {**data, 'ownerUid': uid}, merge=True)

    if runner is None:
        from google.cloud import firestore
        return firestore.transactional(operation)(db.transaction())
    return runner(operation)
