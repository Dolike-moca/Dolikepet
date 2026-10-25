"""Single-source material registry. No command touches pet food or stomach data."""
from pathlib import Path
import argparse, hashlib, json, shutil, sys

GAME = Path(__file__).resolve().parents[1]
PROJECT = GAME.parent
MANIFEST = GAME / 'assets/manifest.json'

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read_manifest():
    return json.loads(MANIFEST.read_text(encoding='utf-8'))

def checked(relative):
    path = (GAME / relative).resolve()
    if not path.is_relative_to(GAME) or any(p in ('猫的饭盆','猫的胃袋') for p in path.parts):
        raise ValueError(f'Not a managed project path: {relative}')
    return path

def sync(data):
    for entry in data['files']:
        source = checked(entry['source'])
        if digest(source) != entry['sha256']:
            raise ValueError(f"Unregistered source change: {entry['source']}; run register after review")
        for destination in entry.get('copies', []):
            target = checked(destination)
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or digest(target) != entry['sha256']:
                shutil.copy2(source, target)
    # Texture import options affect pixels even when the source PNG is identical.
    # Preserve the approved Godot sidecars in clean source checkouts as well.
    imports = GAME / 'assets/imports.json'
    if imports.is_file():
        for entry in json.loads(imports.read_text(encoding='utf-8'))['files']:
            target = checked(entry['path'])
            payload = entry['content'].encode('utf-8')
            if hashlib.sha256(payload).hexdigest() != entry['sha256']:
                raise ValueError('Unregistered import setting: ' + entry['path'])
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() or target.read_bytes() != payload:
                target.write_bytes(payload)

def check(data):
    errors = []
    for entry in data['files']:
        for relative in [entry['source'], *entry.get('copies', [])]:
            path = checked(relative)
            if not path.is_file() or digest(path) != entry['sha256']:
                errors.append(relative)
    if errors:
        raise ValueError('Missing or unsynchronised assets:\n'+'\n'.join(errors))
    print(f"PASS: {len(data['files'])} registered sources; all generated copies match")

def dependencies():
    # Kept outside the distributable Game tree. Optional explicit pip installation.
    vendor = PROJECT / '_tools/psd-lib'
    if vendor.exists(): sys.path.insert(0,str(vendor))

def make_psd(data):
    dependencies()
    from PIL import Image
    from psd_tools import PSDImage
    from psd_tools.api.layers import PixelLayer, Group
    from psd_tools.constants import Compression
    import math
    def placed(layer):
        im = Image.open(checked(layer['source'])).convert('RGBA')
        if 'crop' in layer: im=im.crop(tuple(layer['crop']))
        if 'affine' in layer:
            a,b,c,d,tx,ty = layer['affine']
            det=a*d-b*c
            inv=(d/det,-c/det,(c*ty-d*tx)/det,-b/det,a/det,(b*tx-a*ty)/det)
            im=im.transform((2048,2048),Image.Transform.AFFINE,inv,Image.Resampling.BICUBIC)
            bbox=im.getbbox(); return im.crop(bbox),bbox[:2]
        if 'size' in layer: im=im.resize(tuple(layer['size']),Image.Resampling.LANCZOS)
        return im,layer.get('position',[0,0])
    def add(parent, layer):
        im,xy=placed(layer)
        item=PixelLayer.frompil(im,parent,layer['name'],top=int(xy[1]),left=int(xy[0]),compression=Compression.RLE)
        item.visible=layer.get('visible',True)
        return item
    def save_transparent(document, path):
        # PSD's negative layer count declares the merged alpha as transparency.
        # Preserve both layer alpha and the thumbnail when opened in other tools.
        document.background_color = None
        info = document._record.layer_and_mask_information.layer_info
        info.layer_count = -abs(info.layer_count)
        document.save(path,encoding='utf-8')
    psd=PSDImage.new('RGBA',(2048,2048),color=(0,0,0,0))
    base=Group.new(psd,'01_正式站姿_最新素材')
    for layer in data['baseLayers']: add(base,layer)
    for specification in data['variantGroups']:
        group=Group.new(psd,specification['name']); group.visible=False
        for layer in specification['layers']: add(group,layer)
    save_transparent(psd,GAME/'DesktopPet.Psd')
    # Same 30 names/order retain the existing Cubism ArtMesh and parameter contract.
    cubism=PSDImage.new('RGBA',(2048,2048),color=(0,0,0,0))
    for layer in data['baseLayers']: add(cubism,layer)
    save_transparent(cubism,GAME/'model/source/DesktopPet-base.psd')
    proof=PSDImage.open(GAME/'DesktopPet.Psd')
    count=sum(1 for item in proof.descendants() if not item.is_group())
    preview=proof.composite()
    if preview.mode!='RGBA' or preview.getpixel((0,0))[3]!=0:
        raise ValueError('PSD merged transparency was not preserved')
    print(f'PASS: DesktopPet.Psd reopened, {count} editable layers, {proof.size}')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['check','sync','psd','register'])
    args=parser.parse_args(); data=read_manifest()
    if args.command=='register':
        for entry in data['files']: entry['sha256']=digest(checked(entry['source']))
        MANIFEST.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        print('Registered current source hashes; review changes before release.')
    elif args.command=='sync': sync(data); check(data)
    elif args.command=='psd': check(data); make_psd(data)
    else: check(data)

if __name__=='__main__': main()
