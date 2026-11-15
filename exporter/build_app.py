#!/usr/bin/env python3
"""Build the native Mac UI. Python 3 and FFmpeg remain external runtime tools."""
import argparse
import os
import platform
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or output.suffix != '.app':
        raise SystemExit('Choose a new .app output path; existing apps are not overwritten')
    root = Path(__file__).resolve().parent
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='tcv-export-build-', dir=output.parent) as directory:
        work = Path(directory)
        binary = work / 'ChoicerExporter'
        architecture = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
        subprocess.run(['swiftc','-parse-as-library','-O','-target',architecture+'-apple-macosx13.0','-module-cache-path',str(work/'cache'),str(root/'ExporterApp.swift'),'-o',str(binary)],check=True)
        app = work / 'Choicer Voicer Exporter.app'
        (app/'Contents/MacOS').mkdir(parents=True)
        (app/'Contents/Resources').mkdir()
        shutil.copy2(binary, app/'Contents/MacOS/ChoicerExporter')
        shutil.copy2(root/'exporter.py', app/'Contents/Resources/exporter.py')
        info = {'CFBundleIdentifier':'dev.zeriax.tcv.exporter','CFBundleExecutable':'ChoicerExporter','CFBundleName':'Choicer Voicer Exporter','CFBundleDisplayName':'Choicer Voicer Exporter','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.0','CFBundleVersion':'1','LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication'}
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
        shutil.move(str(app),output)
    print(output)


if __name__ == '__main__': main()
