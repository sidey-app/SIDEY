#!/usr/bin/env python3
"""Round 5: one quack per impact, clean cannon boom, preserve selected PCM."""
import importlib.util
import json
import math
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('round4',ROOT.parent/'round-4/generate_audio.py')
r4=importlib.util.module_from_spec(spec); spec.loader.exec_module(r4)
RATE=r4.RATE
SELECTED={'patch_soft_ball':'A','mini_paprika':'C','banana':'B','dust_bath_pouch':'C','starlight_orb':'B'}


def lowpass(values,hz):
    # Cascaded one-pole sections remove the brittle high-frequency texture.
    alpha=1-math.exp(-2*math.pi*hz/RATE)
    output=list(values)
    for _ in range(3):
        state=0
        for i,x in enumerate(output):
            state+=alpha*(x-state); output[i]=state
    return output


def finish(values,tail=.045):
    # Linear gain only. No tanh, clipping, saturation or hard limiting.
    slow=0; alpha=1-math.exp(-2*math.pi*25/RATE)
    result=[]
    for i,x in enumerate(values):
        slow+=alpha*(x-slow)
        fade=min(1,i/(RATE*.0015))*min(1,(len(values)-1-i)/(RATE*tail))
        result.append((x-slow)*fade)
    rms=math.sqrt(sum(x*x for x in result)/len(result))
    gain=min(.070/rms,10**(-14/20)/max(abs(x) for x in result))
    return [x*gain for x in result]


def duck(variant):
    # Exactly one contiguous source quack: no duplication, echo, or second event.
    return finish(r4.source('duck',speed=[1.0,1.15,.92][variant]),tail=.015)


def cannon(variant):
    duration=[.48,.66,.40][variant]
    speed=[.90,.72,1.05][variant]
    cutoff=[1050,720,1400][variant]
    attack=r4.source('cannon',speed=speed,limit=duration)
    attack=lowpass(attack,cutoff)
    # Restore the body of a pressure blast instead of amplifying crackly source peaks.
    rms=math.sqrt(sum(x*x for x in attack)/len(attack))
    attack=[x*(.30/rms) for x in attack]
    output=[]
    for i in range(round(duration*RATE)):
        t=i/RATE
        fundamental=[92,66,116][variant]
        # A single low, decaying pressure impulse with simultaneous lower overtones.
        body=(math.sin(2*math.pi*fundamental*t)
              +.34*math.sin(2*math.pi*fundamental*1.53*t)
              +.17*math.sin(2*math.pi*fundamental*2.17*t))
        body*=math.exp(-[12,8.5,17][variant]*t)
        blast=(attack[i] if i<len(attack) else 0)*math.exp(-[4,2.5,6][variant]*t)
        output.append([.75,1.0,.62][variant]*body+blast)
    return finish(output,tail=.065)


def main():
    output=ROOT/'audio'; output.mkdir(exist_ok=True)
    previous=json.loads((ROOT.parent/'round-4/audio-manifest.json').read_text())
    sounds=[]; groups=[]
    for identifier,label,description,choices,maker in [
        ('throwable_squeaky_duck','삑삑 오리','한 번 맞으면 꽥 한 번. 울음 높이와 길이만 비교합니다.',
         ['꽥 · 원래 오리 음높이','꽥! · 조금 높고 짧게','꽥 · 조금 낮고 둥글게'],duck),
        ('throwable_toy_cannon','미니 대포','낮은 폭발 울림. 거친 explosion2 혼합과 포화 처리를 제거했습니다.',
         ['펑 · 짧은 포성 울림','쿵펑 · 더 낮고 긴 울림','펑! · 빠르고 또렷한 폭발'],cannon)
    ]:
        groups.append({'id':identifier,'label':label,'description':description,'kind':'hit','object_id':identifier})
        for v,description in enumerate(choices):
            option='ABC'[v]; name=f'{identifier}-{option.lower()}-v5'
            values=maker(v); single=output/(name+'.wav'); r4.prior.save_wav(single,values)
            values=r4.prior.read_wav(single)
            interval=.5 if maker==duck else 1.0
            repeat=output/(name+'-repeat.wav'); r4.prior.save_wav(repeat,r4.prior.repeated(values,interval))
            sounds.append({'id':name,'group_id':identifier,'kind':'hit','object_id':identifier,'label':label+' '+option,'option':option,
               'description':description,'duration_seconds':len(values)/RATE,'repeat_interval_seconds':interval,
               'file':'audio/'+single.name,'repeat_file':'audio/'+repeat.name,'sha256':r4.prior.sha(single),'repeat_sha256':r4.prior.sha(repeat),
               'approval':'pending','selection':'pending','trigger':'impact','quacks_per_impact':1 if maker==duck else 0,
               'sample_rate':RATE,'channels':1,'bit_depth':16,'source_ids':['duck' if maker==duck else 'cannon'],
               'processing':'Linear gain and fades; no saturation or clipping. Cannon: low-pass source and original simultaneous bass resonances.',
               'peak_dbfs':round(20*math.log10(max(abs(x) for x in values)),2),
               'rms_dbfs':round(20*math.log10(math.sqrt(sum(x*x for x in values)/len(values))),2)})
    for group in previous['groups']:
        identifier=group['id']
        if identifier not in SELECTED and identifier!='throwable_bouncy_heart': continue
        group={k:v for k,v in group.items() if not k.startswith('comparison_')}
        group['description']='4차 선택 확정 · 원본과 음량 그대로.' if identifier in SELECTED else '미선택 · 수정 요청이 없어 4차 세 후보를 그대로 보존했습니다.'
        groups.append(group)
        for item in previous['sounds']:
            if item['group_id']!=identifier: continue
            if identifier in SELECTED and item['option']!=SELECTED[identifier]: continue
            item=item.copy(); item['carried_from']='round-4'
            if identifier in SELECTED:
                item.update(approval='approved',selection='chosen_round_4',approval_evidence='2026-09-10 사용자가 4차 후보 선택과 추가 의견 없음을 전달함.')
            for key in ['file','repeat_file']: shutil.copyfile(ROOT.parent/'round-4'/item[key],ROOT/item[key])
            sounds.append(item)
    for group in groups:
        items=[s for s in sounds if s['group_id']==group['id']]
        if len(items)==1: continue
        values=[0.0]*round(.15*RATE); cues=[]
        for item in items:
            cues.append(len(values)/RATE)
            values+=r4.prior.read_wav(ROOT/item['file'])+[0.0]*round(.65*RATE)
        target=output/(group['id']+'-comparison-v5.wav'); r4.prior.save_wav(target,values)
        group.update(comparison_file='audio/'+target.name,comparison_sha256=r4.prior.sha(target),comparison_cues_seconds=cues)
    manifest={'review_round':5,'approval':'pending','groups':groups,'sounds':sounds,
      'retired_features':['enlargement_sound'],'visual_status':'approved_implemented_on_macos_branch',
      'source_manifest':'../round-4/sources/manifest.json','visual_review':'../round-2/index.html#visual-heading'}
    data=json.dumps(manifest,ensure_ascii=False,indent=2)
    (ROOT/'audio-manifest.json').write_text(data+'\n')
    (ROOT/'review-data.js').write_text('globalThis.sideyAudioCandidates = '+data+';\n')
    print('6 new candidates, 5 selected originals, 3 unchanged heart candidates; no enlargement audio.')

if __name__=='__main__': main()
