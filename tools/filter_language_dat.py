import os, re, sys

profiles = sys.argv[1:] if len(sys.argv) > 1 else ['build/texlive-basic', 'build/texlive-extra']

for root in profiles:
    dat = os.path.join(root, 'texmf-dist/texmf-var/tex/generic/config/language.dat')
    if not os.path.exists(dat):
        continue

    def file_exists(name):
        return bool(os.popen(f'find {root} -name "{name}" 2>/dev/null').read().strip())

    def loader_deps_exist(loader):
        path = os.popen(f'find {root} -name "{loader}" 2>/dev/null').read().strip()
        if not path:
            return False
        with open(path.splitlines()[0]) as f:
            content = f.read()
        deps = re.findall(r'\\input\s+(\S+\.tex)', content)
        if not deps:
            return True
        return any(file_exists(os.path.basename(dep)) for dep in deps)

    lines_out = []
    with open(dat) as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith('%') or stripped == '' or stripped.startswith('='):
                lines_out.append(line)
                continue
            parts = stripped.split()
            if len(parts) >= 2:
                if loader_deps_exist(parts[1]):
                    lines_out.append(line)
                else:
                    print(f'  Dropping: {stripped}')
            else:
                lines_out.append(line)

    with open(dat, 'w') as f:
        f.writelines(lines_out)
    print(f'Done {dat}')
