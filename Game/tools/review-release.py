"""Compare actual rendered RGBA frames and create the before/after review video."""
from pathlib import Path
import argparse,json,sys,subprocess,hashlib
P=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(P/'_tools/psd-lib'))
from PIL import Image,ImageDraw,ImageFont,ImageChops
def main():
    p=argparse.ArgumentParser();p.add_argument('before',type=Path);p.add_argument('after',type=Path);p.add_argument('--pack',type=Path);p.add_argument('--out',type=Path,default=P/'_work/final-review');args=p.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    b=json.loads((args.before/'review.json').read_text(encoding='utf-8'));a=json.loads((args.after/'review.json').read_text(encoding='utf-8'))
    if b['frames']!=a['frames'] or b['fps']!=a['fps']:raise ValueError('Review protocol mismatch')
    if b['frames']!=720 or len(b['hashes'])!=720 or len(a['hashes'])!=720 or b['segments']!=a['segments']:
        raise ValueError('Incomplete review frame hashes or segment mismatch')
    changes=[i for i,(x,y) in enumerate(zip(b['hashes'],a['hashes'])) if x!=y]
    report={'frames':b['frames'],'identicalFrames':b['frames']-len(changes),'changedFrames':changes,'segments':b['segments']}
    if args.pack: report['candidateSha256']=hashlib.sha256(args.pack.read_bytes()).hexdigest()
    (args.out/'visual-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',23)
    small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
    frames=args.out/'frames';frames.mkdir(exist_ok=True)
    contact=Image.new('RGB',(960,8*270),(38,35,47));draw=ImageDraw.Draw(contact)
    for i in range(b['frames']):
        canvas=Image.new('RGB',(900,510),(38,35,47));d=ImageDraw.Draw(canvas)
        d.text((36,18),'整理前',font=font,fill='white');d.text((490,18),'方案 C 整理后',font=font,fill='white')
        for index,directory in enumerate([args.before,args.after]):
            im=Image.open(directory/f'frame-{i:04d}.png').convert('RGBA')
            canvas.paste(im,(15+index*450,55),im)
        d.text((30,476),b['segments'][i//90]+' · '+('逐像素一致' if i not in changes else '差异待检查'),font=small,fill=(202,196,215))
        canvas.save(frames/f'frame-{i:04d}.png')
        if i%90==44:
            preview=canvas.resize((450,255),Image.Resampling.LANCZOS)
            contact.paste(preview,(10,i//90*270+5))
            diff=ImageChops.difference(Image.open(args.before/f'frame-{i:04d}.png').convert('RGBA'),Image.open(args.after/f'frame-{i:04d}.png').convert('RGBA'))
            draw.text((480,i//90*270+55),b['segments'][i//90],font=font,fill='white')
            draw.text((480,i//90*270+95),'一致' if diff.getbbox(alpha_only=False) is None else '有像素差异',font=font,fill=(190,230,190))
    contact.save(args.out/'contact-sheet.png')
    ffmpeg=next((P/'_tools/runtime/video-tools').rglob('ffmpeg*.exe'))
    subprocess.run([str(ffmpeg),'-y','-framerate',str(b['fps']),'-i',str(frames/'frame-%04d.png'),'-c:v','libx264','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(args.out/'C-before-after.mp4')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()
