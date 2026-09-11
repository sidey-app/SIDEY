#!/usr/bin/env python3
"""One lip pop per heart impact; three distinct chat-bubble sound directions."""
import importlib.util
import json
import math
from pathlib import Path
import shutil
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('round6',ROOT.parent/'round-6/generate_audio.py')
r6=importlib.util.module_from_spec(spec); spec.loader.exec_module(r6)
RATE=r6.RATE
io=r6.r5.r4.prior


def heart(v):
    source,speed,*_=r6.SPECS[v]
    # Preserve exactly the first review pop from V6; remove the second entirely.
    return r6.pop(source,speed)


def chat(v):
    duration=[.16,.11,.30][v]
    if v==1:
        wood=r6.r5.r4.source('impactWood_light_000',speed=.84,limit=duration,lowpass=1600)
        return r6.r5.finish(wood,tail=.018)
    values=[]
    phase=0
    for i in range(round(duration*RATE)):
        t=i/RATE
        if v==0:
            # A compact droplet resonance, with the pitch settling within the first 12ms.
            hz=760+760*math.exp(-t/.012)
            phase+=2*math.pi*hz/RATE
            value=(math.sin(phase)+.08*math.sin(phase*2))*math.exp(-t*34)
        else:
            # A single glass chime: simultaneous partials, never a repeated notification.
            value=(math.sin(2*math.pi*1174.66*t)*math.exp(-t*12)
                   +.20*math.sin(2*math.pi*2349.32*t)*math.exp(-t*25)
                   +.07*math.sin(2*math.pi*3253*t)*math.exp(-t*42))
        values.append(value)
    return r6.r5.finish(values,tail=.030)


def main():
    output=ROOT/'audio'; output.mkdir(exist_ok=True)
    previous=json.loads((ROOT.parent/'round-6/audio-manifest.json').read_text())
    groups=[]; sounds=[]
    for identifier,label,kind,descriptions,maker in [
      ('throwable_bouncy_heart','통통 하트 · 팝 한 번','hit',
       ['뾲 · 짧고 동그란 입술 팝','뾲 · 조금 더 말랑한 입술 팝','뾲! · 빠르고 또렷한 입술 팝'],heart),
      ('chat_bubble','채팅 말풍선','chat',
       ['물방울 톡 · 둥글고 가벼운 알림','나무 톡 · 짧고 담백한 알림','작은 종 딩 · 맑고 은은한 알림'],chat)
    ]:
        group={'id':identifier,'label':label,'kind':kind,'object_id':identifier if kind=='hit' else None,
          'description':'한 번 맞을 때 입술 팝 한 번. 6차의 첫 팝만 그대로 남겼습니다.' if kind=='hit' else '새 채팅 말풍선이 나타날 때의 소리 방향 세 가지입니다. 각 버튼은 말풍선 한 개의 알림입니다.'}
        groups.append(group)
        for v,description in enumerate(descriptions):
            name=f'{identifier}-{"abc"[v]}-v7'; values=maker(v)
            single=output/(name+'.wav'); io.save_wav(single,values); values=io.read_wav(single)
            interval=.5 if kind=='hit' else 1.0
            repeat=output/(name+'-repeat.wav'); io.save_wav(repeat,io.repeated(values,interval))
            sounds.append({'id':name,'group_id':identifier,'kind':kind,'object_id':group['object_id'],'label':('통통 하트' if kind=='hit' else label)+' '+'ABC'[v],
              'option':'ABC'[v],'description':description,'duration_seconds':len(values)/RATE,'repeat_interval_seconds':interval,
              'file':'audio/'+single.name,'repeat_file':'audio/'+repeat.name,'sha256':io.sha(single),'repeat_sha256':io.sha(repeat),
              'approval':'pending','selection':'pending','trigger':'impact' if kind=='hit' else 'chat_bubble_appeared',
              'events_per_sample':1,'pops_per_impact':1 if kind=='hit' else None,
              'sample_rate':RATE,'channels':1,'bit_depth':16,
              'source_ids':['mouth-'+r6.SPECS[v][0]] if kind=='hit' else ['impactWood_light_000'] if v==1 else [],
              'provenance':'V6 first lip pop, unchanged PCM.' if kind=='hit' else 'Edited CC0 Kenney wood impact.' if v==1 else 'Original deterministic synthesis; no recordings.',
              'peak_dbfs':round(20*math.log10(max(abs(x) for x in values)),2)})
    for oldgroup in previous['groups']:
        selected=[s for s in previous['sounds'] if s['group_id']==oldgroup['id'] and s['approval']=='approved']
        if not selected: continue
        assert len(selected)==1
        groups.append({k:v for k,v in oldgroup.items() if not k.startswith('comparison_')})
        item=selected[0].copy(); item['carried_from']='round-6'
        for key in ['file','repeat_file']: shutil.copyfile(ROOT.parent/'round-6'/item[key],ROOT/item[key])
        sounds.append(item)
    for g in groups[:2]:
        values=[0.0]*round(.15*RATE); cues=[]
        for s in sounds:
            if s['group_id']==g['id']:
                cues.append(len(values)/RATE)
                values+=io.read_wav(ROOT/s['file'])+[0.0]*round(.65*RATE)
        target=output/(g['id']+'-comparison-v7.wav'); io.save_wav(target,values)
        g.update(comparison_file='audio/'+target.name,comparison_sha256=io.sha(target),comparison_cues_seconds=cues)
    m={'review_round':7,'approval':'pending','groups':groups,'sounds':sounds,'retired_features':['enlargement_sound'],
       'visual_status':'approved_implemented_on_macos_branch','mouth_source_manifest':'../round-6/sources/manifest.json',
       'prior_source_manifest':'../round-4/sources/manifest.json','visual_review':'../round-2/index.html#visual-heading',
       'chat_scope':'Sound-direction review only; own messages and settings behavior to be confirmed before implementation.'}
    data=json.dumps(m,ensure_ascii=False,indent=2)
    (ROOT/'audio-manifest.json').write_text(data+'\n'); (ROOT/'review-data.js').write_text('globalThis.sideyAudioCandidates = '+data+';\n')
    print('3 single-pop hearts, 3 chat sounds, 7 selected originals; 28 WAVs.')
if __name__=='__main__': main()
