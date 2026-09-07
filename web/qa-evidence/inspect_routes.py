import re
import json

def inspect_flask_routes():
    with open('web/server.py', 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    routes = []
    current_route = None
    for idx, line in enumerate(lines):
        line_strip = line.strip()
        if '@app.route(' in line_strip or '@bp.route(' in line_strip:
            m = re.search(r'route\((["\'][^"\']+["\'])(?:,\s*methods=\[([^\]]+)\])?', line_strip)
            if m:
                path = m.group(1).strip("'\"")
                methods = m.group(2) if m.group(2) else "'GET'"
                methods = [x.strip(" '\"") for x in methods.split(',')]
                # inspect following lines for def and decorators
                decorators = []
                func_name = None
                for j in range(max(0, idx - 4), min(len(lines), idx + 8)):
                    lj = lines[j].strip()
                    if lj.startswith('@') and 'route' not in lj:
                        decorators.append(lj)
                    if lj.startswith('def '):
                        func_name = lj.split('def ')[1].split('(')[0]
                        break
                routes.append({
                    'path': path,
                    'methods': methods,
                    'function': func_name,
                    'decorators': decorators,
                    'line': idx + 1
                })
    return routes

def inspect_fastapi_routes():
    with open('web/ai_server/main.py', 'r', encoding='utf-8') as f:
        lines = f.readlines()
    routes = []
    for idx, line in enumerate(lines):
        line_strip = line.strip()
        m = re.search(r'@(?:app|router)\.(get|post|put|delete|patch)\((["\'][^"\']+["\'])', line_strip)
        if m:
            method = m.group(1).upper()
            path = m.group(2).strip("'\"")
            func_name = None
            for j in range(idx, min(len(lines), idx + 8)):
                lj = lines[j].strip()
                if lj.startswith('def ') or lj.startswith('async def '):
                    func_name = re.split(r'def\s+', lj)[1].split('(')[0]
                    break
            routes.append({
                'path': path,
                'method': method,
                'function': func_name,
                'line': idx + 1
            })
    return routes

if __name__ == '__main__':
    flask_r = inspect_flask_routes()
    fastapi_r = inspect_fastapi_routes()
    print(f"Flask routes: {len(flask_r)}")
    for r in flask_r:
        print(f"  {','.join(r['methods']):<12} {r['path']:<45} ({r['function']}) decs={r['decorators']}")
    print(f"\nFastAPI routes: {len(fastapi_r)}")
    for r in fastapi_r:
        print(f"  {r['method']:<8} {r['path']:<45} ({r['function']})")
    
    with open('web/qa-evidence/api/routes_inventory.json', 'w', encoding='utf-8') as f:
        json.dump({'flask': flask_r, 'fastapi': fastapi_r}, f, indent=2)
