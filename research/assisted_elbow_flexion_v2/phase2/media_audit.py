"""Original-source diagnostic thumbnails only; never training inputs or labels."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from phase2_utils import P2,inputs,verify_inputs,dump,sha

def source_frames(job):
    vid,path,requests=job
    cap=cv2.VideoCapture(path);assert cap.isOpened(),path
    records=[]
    try:
        for frame,out in sorted(requests):
            assert cap.set(cv2.CAP_PROP_POS_FRAMES,frame)
            ok,img=cap.read();assert ok,(vid,frame)
            after=cap.get(cv2.CAP_PROP_POS_FRAMES)
            assert abs(after-(frame+1))<.5,(vid,frame,after)
            h,w=img.shape[:2];img=cv2.resize(img,(640,round(h*640/w)),interpolation=cv2.INTER_AREA)
            assert cv2.imwrite(str(out),img)
            records.append({'video_id':vid,'requested_zero_based_frame':frame,'decoder_position_after_read':after,'output':str(out),'sha256':sha(out),'method':'OpenCV FFmpeg seek; reported frame position verified; diagnostic only, not extraction or label evidence'})
    finally:cap.release()
    return records

def main():
    verify_inputs();df,_,pred=inputs();cv2.setNumThreads(1)
    jobs=[];source_paths=[];error_paths={}
    for vid,g in df.groupby('video_id',sort=True):
        mid=g.iloc[len(g)//2];frame=(int(mid.start_frame)+int(mid.end_frame))//2
        out=P2/'media'/f'{vid}.jpg';requests=[(frame,out)];source_paths.append((vid,out))
        for _,r in g[~pred.is_correct.loc[g.index].to_numpy()].iterrows():
            raw=np.load(P2.parent/'features/per_repetition'/f'{r.repetition_id}.npz')
            a=raw['kinematics'][:,0];finite=np.isfinite(a)
            middle=int(raw['frame_indices'][np.nanargmin(a)]) if finite.any() else (int(r.start_frame)+int(r.end_frame))//2
            frames=[int(r.start_frame),middle,int(r.end_frame)]
            files=[P2/'media'/f'{r.repetition_id}_{j}.jpg' for j in range(3)]
            requests+=list(zip(frames,files));error_paths[r.repetition_id]=files
        jobs.append((vid,g.source_video.iloc[0],requests))
    with ThreadPoolExecutor(max_workers=3) as pool:
        records=[r for batch in pool.map(source_frames,jobs) for r in batch]
    dump(P2/'audits/diagnostic_thumbnail_audit.json',records)
    font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
    for page,start in enumerate(range(0,len(source_paths),9),1):
        canvas=Image.new('RGB',(1920,1200),'white');draw=ImageDraw.Draw(canvas)
        for k,(vid,path) in enumerate(source_paths[start:start+9]):
            xx=(k%3)*640;yy=(k//3)*400
            canvas.paste(Image.open(path).resize((640,360)),(xx,yy))
            pp=pred[pred.video_id==vid];acc=pp.is_correct.mean()
            draw.text((xx+8,yy+365),f'{vid} | N={len(pp)} | accuracy={acc*100:.2f}%',fill='black',font=font)
        canvas.save(P2/'plots'/f'source_contact_{page}.jpg',quality=92)
    error_rows=[]
    for rid,files in error_paths.items():
        r=df[df.repetition_id==rid].iloc[0];pp=pred[pred.repetition_id==rid].iloc[0]
        canvas=Image.new('RGB',(1920,405),'white');draw=ImageDraw.Draw(canvas)
        for j,f in enumerate(files):canvas.paste(Image.open(f).resize((640,360)),(j*640,0))
        draw.text((8,367),f'{rid} | {r.hand} | human {r.label}, predicted {pp.predicted_label} | start / measured minimum / end',fill='black',font=font)
        out=P2/'plots/errors'/f'{rid}_frames.jpg';canvas.save(out,quality=92)
        error_rows.append({'repetition_id':rid,'frame_strip':str(out),'trace':str(P2/'plots/errors'/f'{rid}.png')})
    import pandas as pd
    pd.DataFrame(error_rows).to_csv(P2/'audits/individual_error_artifacts.csv',index=False)
    print(json.dumps({'source_thumbnails':29,'error_frame_strips':len(error_paths),'diagnostic_frame_reads':len(records)}))

if __name__=='__main__':main()
