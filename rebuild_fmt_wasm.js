const fs = require('fs');
const path = require('path');

const profile = process.argv[2];
const fmtDir = process.argv[3];

async function rebuildFormats() {
    const hostTexlive = `./build/texlive-${profile}`;

    console.log(`Loading busytex module...`);
    const BusytexModule = require('./build/wasm/busytex.js');

    const Module = await BusytexModule({
        locateFile: (filename, prefix) => {
            if (filename.endsWith('.wasm')) {
                return './build/wasm/' + filename;
            }
            return prefix + filename;
        },
        noInitialRun: true,
        thisProgram: '/bin/busytex',
        print: (text) => console.log(text),
        printErr: (text) => console.error(text),
    });

    console.log('Setting up base filesystem...');
    ensureDir(Module.FS, '/bin');
    Module.FS.writeFile('/bin/busytex', '');

    ensureDir(Module.FS, '/etc');
    Module.FS.writeFile('/etc/passwd', 'web_user:x:0:0:emscripten:/home/web_user:/bin/false\n');

    console.log(`Copying ${hostTexlive} to /texlive...`);
    let fileCount = 0;

    function copyDir(hostDir, memfsDir) {
        ensureDir(Module.FS, memfsDir);

        const entries = fs.readdirSync(hostDir, { withFileTypes: true });
        for (const entry of entries) {
            const hostFullPath = path.join(hostDir, entry.name);
            const memfsFullPath = memfsDir + '/' + entry.name;

            if (entry.isDirectory()) {
                copyDir(hostFullPath, memfsFullPath);
            } else if (entry.isFile()) {
                try {
                    const content = fs.readFileSync(hostFullPath);
                    Module.FS.writeFile(memfsFullPath, content);
                    fileCount++;
                    if (fileCount % 1000 === 0) {
                        console.log(`  Copied ${fileCount} files...`);
                    }
                } catch (e) {
                }
            }
        }
    }

    copyDir(hostTexlive, '/texlive');
    console.log(`Copied ${fileCount} files total`);

    console.log('\nSetting up environment...');
    Module.ENV['TEXMFCNF'] = '/texlive/texmf-dist/web2c';
    Module.ENV['TEXMFDIST'] = '/texlive/texmf-dist';
    Module.ENV['TEXMFVAR'] = '/texlive/texmf-dist/texmf-var';
    Module.ENV['TEXMFCONFIG'] = '/texlive/texmf-dist/texmf-config';
    Module.ENV['TEXMFLOCAL'] = '/texlive/texmf-dist/texmf-local';
    Module.ENV['TEXMFROOT'] = '/texlive';
    Module.ENV['TEXMFHOME'] = '/texlive/texmf-dist';
    Module.ENV['FONTCONFIG_PATH'] = '/texlive';
    Module.ENV['FONTCONFIG_FILE'] = '/texlive/fonts.conf';
    Module.ENV['TEXMFSYSVAR'] = '/texlive/texmf-dist/texmf-var';
    Module.ENV['TEXMFSYSCONFIG'] = '/texlive/texmf-dist/texmf-config';

    function findIniFile(FS, name) {
        const candidates = findFile(FS, '/texlive', name, 8);
        return candidates.find(p => p.includes('texmf-dist')) || candidates[0] || null;
    }
    console.log('lualatex.ini:', findIniFile(Module.FS, 'lualatex.ini'));
    console.log('pdflatex.ini:', findIniFile(Module.FS, 'pdflatex.ini'));
    console.log('xelatex.ini:', findIniFile(Module.FS, 'xelatex.ini'));

    const formats = {
        'luahbtex/luahblatex.fmt': {
            args: ['luahbtex', '-ini', '-jobname=luahblatex', '-progname=luahblatex'],
            iniFile: findIniFile(Module.FS, 'lualatex.ini')
        },
        'pdftex/pdflatex.fmt': {
            args: ['pdftex', '-ini', '-etex', '-jobname=pdflatex', '-progname=pdflatex'],
            iniFile: findIniFile(Module.FS, 'pdflatex.ini')
        },
        'xetex/xelatex.fmt': {
            args: ['xetex', '-ini', '-etex', '-jobname=xelatex', '-progname=xelatex'],
            iniFile: findIniFile(Module.FS, 'xelatex.ini')
        },
    };

    for (const [fmtPath, config] of Object.entries(formats)) {
        console.log(`\n${'='.repeat(60)}`);
        console.log(`Rebuilding ${fmtPath}...`);

        const args = [...config.args, config.iniFile];
        console.log(`Command: ${args.join(' ')}`);

        const fmtSubdir = path.dirname(fmtPath);
        const workDir = `/texlive/texmf-dist/texmf-var/web2c/${fmtSubdir}`;

        ensureDir(Module.FS, workDir);
        Module.FS.chdir(workDir);
        console.log(`Working directory: ${Module.FS.cwd()}`);

        const fmtFileName = path.basename(fmtPath);

        try {
            console.log('\nExecuting format generation...');
            const exitCode = Module.callMain(args);
            console.log(`\nExit code: ${exitCode}`);

            const filesInDir = Module.FS.readdir(workDir);
            console.log(`Files in ${workDir}:`, filesInDir);

            const fmtExists = Module.FS.analyzePath(workDir + '/' + fmtFileName).exists;

            if (!fmtExists) {
                const logPath = `${workDir}/luahblatex.log`;
                if (Module.FS.analyzePath(logPath).exists) {
                    const logContent = Module.FS.readFile(logPath, { encoding: 'utf8' });
                    console.log('\n--- luahblatex.log (last 100 lines) ---');
                    const lines = logContent.split('\n');
                    console.log(lines.slice(-100).join('\n'));
                    console.log('--- end of log ---\n');
                }
                throw new Error(`Format file ${fmtFileName} was not created`);
            }

            console.log(`Format file ${fmtFileName} exists, reading...`);
            const fmtFile = Module.FS.readFile(fmtFileName);

            if (fmtFile.length < 1000) {
                throw new Error(`Format file is too small (${fmtFile.length} bytes), likely invalid`);
            }

            const outputPath = path.join(fmtDir, fmtPath);
            fs.mkdirSync(path.dirname(outputPath), { recursive: true });
            fs.writeFileSync(outputPath, fmtFile);

            console.log(`✓ Successfully rebuilt ${fmtPath} (${fmtFile.length} bytes)`);

        } catch (e) {
            console.error(`✗ Failed to rebuild ${fmtPath}:`, e.message || e);
            process.exit(1);
        }
    }

    console.log('\n✓ All formats rebuilt successfully');
}

function ensureDir(FS, dirPath) {
    const parts = dirPath.split('/').filter(p => p);
    let current = '';
    for (const part of parts) {
        current += '/' + part;
        try {
            const info = FS.analyzePath(current);
            if (!info.exists) {
                FS.mkdir(current);
            }
        } catch (e) {
            try {
                FS.mkdir(current);
            } catch (e2) {
            }
        }
    }
}

function findFile(FS, startPath, filename, maxDepth) {
    const results = [];

    function search(currentPath, depth) {
        if (depth > maxDepth) return;

        try {
            const entries = FS.readdir(currentPath);
            for (const entry of entries) {
                if (entry === '.' || entry === '..') continue;

                const fullPath = currentPath + '/' + entry;

                try {
                    const stat = FS.stat(fullPath);
                    if (FS.isDir(stat.mode)) {
                        search(fullPath, depth + 1);
                    } else if (entry === filename) {
                        results.push(fullPath);
                    }
                } catch (e) {
                }
            }
        } catch (e) {
        }
    }

    search(startPath, 0);
    return results;
}

rebuildFormats().catch(e => {
    console.error('Fatal error:', e);
    if (e.stack) console.error(e.stack);
    process.exit(1);
});