import io
import os
import sys

import pytest
from flask import Flask
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.abspath(os.path.join(HERE, '..')))
sys.path.insert(0, HERE)

import test_vehicle_catalog as base  # noqa: E402
from vehicle_catalog import create_catalog_blueprint, normalize_catalog_document  # noqa: E402
from vehicle_media import (  # noqa: E402
    MAX_ANGLES,
    SPIN_MIN_ANGLES,
    AzureBlobMediaStore,
    add_showroom_angle,
    process_vehicle_image,
    remove_light_background,
    sanitize_showroom,
    store_vehicle_image,
    update_showroom,
)


class FakeStore:
    def __init__(self):
        self.puts = []

    def put(self, path, data, content_type):
        self.puts.append((path, len(data), content_type))
        return f'https://media.example.net/vehicle-media/{path}'

    def owns(self, url):
        return url.startswith('https://media.example.net/')


def studio_photo(width=800, height=500, background=(250, 250, 250)):
    """Scooter-like dark body on a white backdrop, with an enclosed white
    highlight (must stay opaque: it does not touch the border)."""
    image = Image.new('RGB', (width, height), background)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((180, 160, 620, 380), radius=40, fill=(30, 40, 60))
    draw.ellipse((200, 330, 300, 430), fill=(15, 15, 15))
    draw.ellipse((500, 330, 600, 430), fill=(15, 15, 15))
    draw.rectangle((360, 220, 440, 260), fill=(252, 252, 252))  # enclosed highlight
    return image


def png(image):
    buffer = io.BytesIO()
    image.save(buffer, 'PNG')
    return buffer.getvalue()


def asset(checksum, name='a'):
    return {
        'thumbnailUrl': f'https://media.example.net/{name}/t.webp',
        'mediumUrl': f'https://media.example.net/{name}/m.webp',
        'heroUrl': f'https://media.example.net/{name}/h.webp',
        'checksum': checksum,
        'credit': '© VinFast',
    }


def test_white_studio_background_becomes_transparent_but_enclosed_white_stays():
    rgba, removed = remove_light_background(studio_photo())
    assert removed is True
    alpha = rgba.getchannel('A')
    assert alpha.getpixel((5, 5)) == 0
    assert alpha.getpixel((790, 490)) == 0
    assert alpha.getpixel((400, 200)) == 255  # body
    assert alpha.getpixel((400, 240)) == 255  # enclosed white highlight


def pale_scooter_with_floor_shadow():
    """Mint body almost as light as a mint-tinted backdrop, on a soft floor shadow."""
    backdrop = (246, 251, 249)
    image = Image.new('RGB', (800, 500), backdrop)
    # Floor shadow: the backdrop darkened without changing its tint, blurred.
    shade = Image.new('L', (800, 500), 0)
    ImageDraw.Draw(shade).ellipse((140, 400, 660, 470), fill=150)
    shade = shade.filter(ImageFilter.GaussianBlur(14))
    dark = Image.new('RGB', (800, 500), tuple(round(c * 0.55) for c in backdrop))
    image = Image.composite(dark, image, shade)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((180, 120, 620, 380), radius=40, fill=(226, 233, 225))  # pale body
    draw.ellipse((200, 330, 300, 430), fill=(20, 20, 20))
    draw.ellipse((500, 330, 600, 430), fill=(20, 20, 20))
    return image


def test_pale_body_survives_and_floor_shadow_is_removed():
    rgba, removed = remove_light_background(pale_scooter_with_floor_shadow())
    assert removed is True
    alpha = rgba.getchannel('A')
    assert alpha.getpixel((5, 5)) == 0
    assert alpha.getpixel((400, 200)) == 255  # pale body, only ~20 levels off the backdrop
    assert alpha.getpixel((250, 380)) == 255  # tyre
    assert alpha.getpixel((400, 440)) == 0  # floor shadow between the wheels
    assert alpha.getpixel((170, 440)) == 0
    # The edge is unmixed: no light backdrop halo next to the dark tyre.
    tyre_edge = [rgba.getpixel((x, 420)) for x in range(212, 224)]
    assert all(px[3] == 0 or max(px[:3]) < 80 for px in tyre_edge)
    # Backdrop pixels beside the pale body stay fully transparent (no faint rim).
    body_edge = [rgba.getpixel((x, 300)) for x in range(170, 184)]
    assert all(px[3] == 0 for px in body_edge if px[:3] == (246, 251, 249))
    assert body_edge[-1][3] == 255


def test_basic_removal_is_used_without_scipy(monkeypatch):
    import vehicle_media
    monkeypatch.setattr(vehicle_media, 'ndimage', None)
    rgba, removed = vehicle_media.remove_light_background(studio_photo())
    assert removed is True
    assert rgba.getchannel('A').getpixel((5, 5)) == 0
    assert rgba.getchannel('A').getpixel((400, 240)) == 255


def test_photo_without_light_border_is_left_untouched():
    rgba, removed = remove_light_background(studio_photo(background=(40, 90, 60)))
    assert removed is False
    assert rgba.getchannel('A').getpixel((5, 5)) == 255


def test_processing_outputs_alpha_webp_sizes_on_16_by_10_canvas():
    outputs, info = process_vehicle_image(png(studio_photo()))
    assert [label for label, _, _ in outputs] == ['thumbnail', 'medium', 'hero']
    assert info['backgroundRemoved'] is True
    assert abs(info['width'] / info['height'] - 1.6) < 0.01
    thumb = Image.open(io.BytesIO(outputs[0][2]))
    assert thumb.format == 'WEBP' and thumb.mode == 'RGBA'
    assert thumb.width == 320


def test_background_removal_can_be_disabled_and_bad_files_are_rejected():
    _, info = process_vehicle_image(png(studio_photo()), remove_background=False)
    assert info['backgroundRemoved'] is False
    with pytest.raises(ValueError):
        process_vehicle_image(b'not an image')
    with pytest.raises(ValueError):
        process_vehicle_image(b'0' * (10 * 1024 * 1024 + 1))


def test_store_writes_checksummed_immutable_paths():
    store = FakeStore()
    data = png(studio_photo())
    result = store_vehicle_image(
        store, 'evo200', data, media_kind='angle', source_url='https://vinfastauto.com/x',
        credit='© VinFast', license_note='Ảnh chính thức', subpath='red',
    )
    assert len(store.puts) == 3
    assert all(path.startswith('vehicle-catalog/evo200/angle/red/') for path, _, _ in store.puts)
    assert all(ctype == 'image/webp' for _, _, ctype in store.puts)
    assert result['heroUrl'].endswith('/hero.webp')
    assert result['checksum'] and result['backgroundRemoved'] is True


def test_azure_store_validates_names_and_builds_public_urls():
    store = AzureBlobMediaStore('vinfastmedia01', 'vehicle-media')
    assert store.base_url == 'https://vinfastmedia01.blob.core.windows.net/vehicle-media/'
    assert store.owns(store.base_url + 'x.webp')
    assert not store.owns('https://evil.example.com/x.webp')
    with pytest.raises(ValueError):
        AzureBlobMediaStore('Bad_Name', 'vehicle-media')


def test_angles_append_in_order_dedupe_and_drive_primary_image():
    media = {}
    for i in range(3):
        media = add_showroom_angle(
            media, color_id='do-tuoi', color_name='Đỏ tươi', swatch_hex='#c8102e',
            angle_index=None, asset=asset(f'c{i}', f'red{i}'),
        )
    # Re-uploading the same image replaces it instead of duplicating.
    media = add_showroom_angle(
        media, color_id='do-tuoi', color_name='', swatch_hex='', angle_index=0,
        asset=asset('c2', 'red2'),
    )
    color = media['showroom']['colors'][0]
    assert [a['checksum'] for a in color['angles']] == ['c2', 'c0', 'c1']
    assert color['swatchHex'] == '#C8102E'
    assert media['showroom']['defaultColorId'] == 'do-tuoi'
    assert media['heroUrl'] == 'https://media.example.net/red2/h.webp'


def test_angle_and_colour_limits_and_invalid_ids():
    media = {}
    for i in range(MAX_ANGLES):
        media = add_showroom_angle(media, color_id='x', color_name='X', swatch_hex='',
                                   angle_index=None, asset=asset(f'k{i}', f'k{i}'))
    with pytest.raises(ValueError):
        add_showroom_angle(media, color_id='x', color_name='X', swatch_hex='',
                           angle_index=None, asset=asset('extra'))
    with pytest.raises(ValueError):
        add_showroom_angle({}, color_id='Bad Id', color_name='', swatch_hex='',
                           angle_index=None, asset=asset('a'))
    assert SPIN_MIN_ANGLES == 12


def test_update_reorders_by_checksum_never_injects_urls_and_sets_default():
    media = {}
    for color in ('trang', 'den'):
        for i in range(2):
            media = add_showroom_angle(media, color_id=color, color_name=color, swatch_hex='',
                                       angle_index=None, asset=asset(f'{color}{i}', f'{color}{i}'))
    media = update_showroom(media, {
        'defaultColorId': 'den',
        'colors': [
            {'id': 'den', 'name': 'Đen nhám', 'swatchHex': '#111111',
             'angleChecksums': ['den1', 'den0', 'injected']},
            {'id': 'trang', 'angleChecksums': ['trang0']},
            {'id': 'unknown', 'angleChecksums': ['x']},
        ],
    })
    colors = media['showroom']['colors']
    assert [c['id'] for c in colors] == ['den', 'trang']
    assert [a['checksum'] for a in colors[0]['angles']] == ['den1', 'den0']
    assert colors[0]['name'] == 'Đen nhám'
    assert len(colors[1]['angles']) == 1
    assert media['showroom']['defaultColorId'] == 'den'
    assert media['heroUrl'] == 'https://media.example.net/den1/h.webp'
    # Removing every colour clears the showroom and the primary image.
    media = update_showroom(media, {'colors': []})
    assert 'showroom' not in media and 'heroUrl' not in media


def test_sanitize_drops_non_https_assets_and_normalize_keeps_showroom():
    raw = {'colors': [{'id': 'xanh', 'name': 'Xanh', 'swatchHex': 'blue', 'angles': [
        {'heroUrl': 'http://insecure.example/h.webp', 'checksum': 'a'},
        {'heroUrl': 'https://media.example.net/h.webp', 'checksum': 'b'},
    ]}]}
    clean = sanitize_showroom(raw)
    assert [a['checksum'] for a in clean['colors'][0]['angles']] == ['b']
    assert clean['colors'][0]['swatchHex'] == '#C9CDD2'
    normalized = normalize_catalog_document({**base.complete_payload(), 'media': {'showroom': raw}})
    assert normalized['media']['showroom']['colors'][0]['id'] == 'xanh'
    assert normalized['media']['heroUrl'] == 'https://media.example.net/h.webp'


def make_app(db, store):
    def admin(fn):
        def wrapper(*args, **kwargs):
            from flask import request
            request._uid, request._email = 'admin-1', 'admin@example.com'
            return fn(*args, **kwargs)
        wrapper.__name__ = fn.__name__
        return wrapper

    audits = []
    app = Flask(__name__)
    app.register_blueprint(create_catalog_blueprint(
        require_admin=admin, require_auth=admin, get_db=lambda: db,
        audit=lambda *a, **k: audits.append(a), media_store=store,
    ))
    return app, audits


def test_angle_upload_route_requires_rights_and_colour_then_updates_draft():
    db = base.FakeDb({'VehicleCatalogDrafts': {'evo200': {'media': {}}}})
    store = FakeStore()
    app, audits = make_app(db, store)
    client = app.test_client()

    def upload(**form):
        data = {'file': (io.BytesIO(png(studio_photo())), 'evo-01.png'), **form}
        return client.post('/api/admin/vehicle-catalog/evo200/media', data=data,
                           content_type='multipart/form-data')

    assert upload(kind='angle', colorId='do').status_code == 422  # no rights
    assert upload(kind='angle', rightsConfirmed='true').status_code == 422  # no colour
    response = upload(kind='angle', rightsConfirmed='true', colorId='do',
                      colorName='Đỏ', swatchHex='#C8102E', sourceUrl='https://vinfastauto.com')
    assert response.status_code == 200, response.json
    media = db.data['VehicleCatalogDrafts']['evo200']['media']
    assert media['showroom']['colors'][0]['angles'][0]['backgroundRemoved'] is True
    assert media['heroUrl'].startswith('https://media.example.net/')
    assert audits and audits[-1][0] == 'catalog_media_upload'

    reorder = client.put('/api/admin/vehicle-catalog/evo200/showroom', json={
        'defaultColorId': 'do',
        'colors': [{'id': 'do', 'name': 'Đỏ tươi', 'angleChecksums': [
            media['showroom']['colors'][0]['angles'][0]['checksum']]}],
    })
    assert reorder.status_code == 200
    assert db.data['VehicleCatalogDrafts']['evo200']['media']['showroom']['colors'][0]['name'] == 'Đỏ tươi'
    missing = client.put('/api/admin/vehicle-catalog/none/showroom', json={'colors': []})
    assert missing.status_code == 404
