"""Transfer one visible enrollment code to the authorized QA phone, without logs.

Does not submit, rotate codes, fetch auth tokens or actuate a device.
"""
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ADB = 'C:/Users/khanh/AppData/Local/Android/Sdk/platform-tools/adb.exe'
NODE = 'C:/Users/khanh/AppData/Local/npm-cache/_npx/52027bd8fc0022aa/node_modules/node/bin/node.exe'
CLI = 'C:/Users/khanh/AppData/Local/npm-cache/_npx/9e308f29f5e381cc/node_modules/@playwright/cli/playwright-cli.js'


def adb(*args):
    return subprocess.run([ADB, '-s', '8bdf16d1', *args], capture_output=True, check=True, timeout=30)


def main():
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/vinfast-qa-window.xml')
    root = ET.fromstring(adb('shell', 'cat', '/data/local/tmp/vinfast-qa-window.xml').stdout)
    if not any('Xác nhận mã kết nối' in n.get('content-desc', '') for n in root.iter('node')):
        raise ValueError('notAdminCodeForm')
    inputs = [n for n in root.iter('node') if 'EditText' in n.get('class', '')]
    if len(inputs) != 1:
        raise ValueError('unexpectedInputCount')
    if inputs[0].get('text'):
        print(json.dumps({'typed': False, 'reason': 'existingInputPreserved'}))
        return
    script = '''async page => {
      if(new URL(page.url()).hostname!=="victorious-tree-076e47d00.6.azurestaticapps.net") throw Error("unexpectedOrigin");
      const buttons=page.getByTitle("Sao chép mã kết nối",{exact:true});
      if(await buttons.count()!==1) throw Error("ambiguousDevice");
      return {code:(await buttons.first().locator("span").first().textContent())?.trim()};
    }'''
    result = subprocess.run([NODE, CLI, '-s=azure-admin-task82', 'run-code', script],
                            capture_output=True, encoding='utf-8', check=True, timeout=45)
    # Keep CLI output in memory: it contains the short-lived enrollment secret.
    match = re.search(r'### Result\s*(\{[^\n]+\})', result.stdout)
    if not match:
        raise ValueError('missingCodeResult')
    code = json.loads(match[1]).get('code', '')
    if not re.fullmatch('[A-Z0-9]{6}', code):
        raise ValueError('invalidCodeShape')
    bounds = list(map(int, re.findall(r'\d+', inputs[0].get('bounds', ''))))
    adb('shell', 'input', 'tap', str((bounds[0]+bounds[2])//2), str((bounds[1]+bounds[3])//2))
    adb('shell', 'input', 'text', code)
    adb('shell', 'uiautomator', 'dump', '/data/local/tmp/vinfast-qa-window.xml')
    after = ET.fromstring(adb('shell', 'cat', '/data/local/tmp/vinfast-qa-window.xml').stdout)
    verified = any(n.get('text', '').strip() == code for n in after.iter('node')
                   if 'EditText' in n.get('class', ''))
    print(json.dumps({'typed': verified, 'codeLength': 6, 'submitted': False, 'hardwareCommands': 0}))
    if not verified:
        raise ValueError('inputReadbackFailed')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'typed': False, 'failureType': type(error).__name__}))
        raise SystemExit(1)
