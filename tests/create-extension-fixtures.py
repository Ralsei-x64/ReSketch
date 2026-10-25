# SPDX-FileCopyrightText: 2026 Ralsei-x64
# SPDX-License-Identifier: GPL-3.0-only
"""Small local CRX wrappers used to exercise safe unpacking and real CEF loading."""
import io, json, pathlib, struct, sys, zipfile
root=pathlib.Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
def package(name,entries):
    stream=io.BytesIO()
    with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as archive:
        for path,body in entries.items():archive.writestr(path,body)
    # Imports deliberately use unpacked semantics, not signature verification.
    (root/name).write_bytes(b'Cr24'+struct.pack('<II',3,0)+stream.getvalue())
manifest=json.dumps(dict(manifest_version=3,name='__MSG_extName__',default_locale='en',version='1.0',permissions=['storage'],content_scripts=[dict(matches=['http://127.0.0.1/*'],js=['content.js'],run_at='document_idle')],action=dict(default_popup='popup.html'),options_page='options.html'))
package('valid.crx',{'manifest.json':manifest,'_locales/en/messages.json':json.dumps({'extName':{'message':'Local extension fixture'}}),'content.js':"document.documentElement.dataset.extensionFixture='loaded'",'popup.html':'<title>Extension popup</title><p>Popup fixture</p>','options.html':'<title>Extension options</title>'})
package('traversal.crx',{'manifest.json':manifest,'../escape.js':'unsafe'})
package('absolute.crx',{'manifest.json':manifest,'/escape.js':'unsafe'})
package('backslash.crx',{'manifest.json':manifest,'..\\escape.js':'unsafe'})
link=zipfile.ZipInfo('link');link.external_attr=0o120777 << 16
stream=io.BytesIO()
with zipfile.ZipFile(stream,'w') as archive:archive.writestr('manifest.json',manifest);archive.writestr(link,'/tmp')
(root/'symlink.crx').write_bytes(b'Cr24'+struct.pack('<II',3,0)+stream.getvalue())
package('old-manifest.crx',{'manifest.json':json.dumps(dict(manifest_version=2,name='Old',version='1'))})
(root/'bad-header.crx').write_bytes(b'Cr24'+struct.pack('<II',3,0xffffffff)+b'x')
broken_manifest=json.loads(manifest);broken_manifest.pop('default_locale');broken_manifest['name']='Broken extension fixture'
package('broken-script.crx',{'manifest.json':json.dumps(broken_manifest)})
package('bomb.crx',{'manifest.json':manifest,'large.bin':'x'*(129*1024*1024)})
