"""Read QA UI labels in memory, without persisting hierarchy or input values.

The caller must explicitly provide the authorized ADB target. No actuation,
credentials, login or data deletion is performed by this helper.
"""
import argparse
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ADB = 'C:/Users/khanh/AppData/Local/Android/Sdk/platform-tools/adb.exe'


def sanitize(value):
    value = re.sub(r'[^\s@]+@[^\s@]+', '[email]', value)
    value = re.sub(r'https?://\S+', '[url]', value)
    value = re.sub(r'\b[0-9a-fA-F]{12,}\b', '[identifier]', value)
    value = re.sub(r'\b[A-Za-z0-9_-]{20,}\b', '[identifier]', value)
    return value[:600]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--target', required=True)
    args = parser.parse_args()

    def adb(*command):
        return subprocess.run([ADB, '-s', args.target, *command],
                              capture_output=True, check=True, timeout=30).stdout

    temporary = '/data/local/tmp/batterybot-qa-view.xml'
    try:
        adb('shell', 'uiautomator', 'dump', temporary)
        root = ET.fromstring(adb('shell', 'cat', temporary))
        nodes = []
        for node in root.iter('node'):
            if node.get('package') not in {'com.bes.vinbatery', 'com.google.android.permissioncontroller'}:
                continue
            # Never expose field contents, even when accessibility marks it
            # as a non-password field (email and cloud keys are sensitive too).
            is_input = 'EditText' in node.get('class', '')
            label = '[input omitted]' if is_input else '\n'.join(
                filter(None, [node.get('text', ''), node.get('content-desc', '')]))
            if label or node.get('clickable') == 'true':
                nodes.append({'label': sanitize(label),
                              'bounds': node.get('bounds'),
                              'clickable': node.get('clickable'),
                              'enabled': node.get('enabled'),
                              'input': is_input})
        print(json.dumps({'nodes': nodes}, ensure_ascii=False))
    finally:
        # Delete only the hierarchy created by this helper, not app data.
        try:
            adb('shell', 'rm', '-f', temporary)
        except (subprocess.SubprocessError, OSError):
            pass


if __name__ == '__main__':
    try:
        main()
    except (subprocess.SubprocessError, OSError, ET.ParseError) as error:
        # Subprocess exception text can contain the ADB serial. Report type only.
        print(json.dumps({'inspectionFailed': type(error).__name__}))
        raise SystemExit(1)
