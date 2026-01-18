const fs = require('fs');
const path = require('path');

const profile = process.argv[2];
const fmtDir = process.argv[3];

async function rebuildFormats() {
    console.log(`Loading busytex module...`);
    const BusytexModule = require('./build/wasm/busytex.js');

    console.log(`Loading texlive-${profile} data package...`);

    const Module = await BusytexModule({
        locateFile: (filename, prefix) => {
            if (filename.endsWith('.wasm')) {
                return './build/wasm/' + filename;
            }
            if (filename.endsWith('.data')) {
                return './build/wasm/texlive-' + profile + '.data';
            }
            return prefix + filename;
        },
        noInitialRun: true,
        print: (text) => console.log(text),
        printErr: (text) => console.error(text)
    });

    // The data package is automatically loaded by Emscripten via the .js file
    // Check if texlive directory exists
    console.log('Checking filesystem...');
    try {
        const texliveExists = Module.FS.analyzePath('/texlive').exists;
        if (!texliveExists) {
            console.error('ERROR: /texlive directory not found in WASM filesystem');
            console.log('Root directory contents:');
            console.log(Module.FS.readdir('/'));
            process.exit(1);
        }
        console.log('/texlive directory found');
    } catch (e) {
        console.error('Error checking filesystem:', e);
        process.exit(1);
    }

    const formats = {
        'luahbtex/luahblatex.fmt': ['luahbtex', '-ini', '-jobname=luahblatex', '-progname=luahblatex', 'lualatex.ini'],
    };

    for (const [fmtPath, args] of Object.entries(formats)) {
        console.log(`\nRebuilding ${fmtPath}...`);
        console.log(`Command: ${args.join(' ')}`);

        const fmtSubdir = path.dirname(fmtPath);
        const workDir = `/texlive/texmf-dist/texmf-var/web2c/${fmtSubdir}`;

        console.log(`Target directory: ${workDir}`);
        try {
            const dirInfo = Module.FS.analyzePath(workDir);
            if (!dirInfo.exists) {
                console.error(`ERROR: Directory does not exist: ${workDir}`);
                console.log('Creating directory...');
                Module.FS.mkdirTree(workDir);
            }

            Module.FS.chdir(workDir);
            console.log(`Working directory set to: ${Module.FS.cwd()}`);
        } catch (e) {
            console.error(`Failed to change directory: ${e.message}`);
            console.log('Checking parent directories...');
            try {
                console.log('/texlive:', Module.FS.readdir('/texlive'));
                console.log('/texlive/texmf-dist:', Module.FS.readdir('/texlive/texmf-dist'));
            } catch (err) {
                console.error('Cannot read parent directories:', err.message);
            }
            throw e;
        }

        try {
            console.log('Executing format generation...');
            Module.callMain(args);

            const fmtFileName = path.basename(fmtPath);
            console.log(`Reading generated format file: ${fmtFileName}`);

            const fmtFile = Module.FS.readFile(fmtFileName);

            const outputPath = path.join(fmtDir, fmtPath);
            console.log(`Writing to host filesystem: ${outputPath}`);

            fs.mkdirSync(path.dirname(outputPath), { recursive: true });
            fs.writeFileSync(outputPath, fmtFile);

            console.log(`✓ Successfully rebuilt ${fmtPath} (${fmtFile.length} bytes)`);
        } catch (e) {
            console.error(`✗ Failed to rebuild ${fmtPath}:`, e);
            if (e.message) console.error('Error message:', e.message);
            if (e.stack) console.error('Stack:', e.stack);
            process.exit(1);
        }
    }

    console.log('\n✓ All formats rebuilt successfully');
}

rebuildFormats().catch(e => {
    console.error('Fatal error:', e);
    if (e.stack) console.error(e.stack);
    process.exit(1);
});