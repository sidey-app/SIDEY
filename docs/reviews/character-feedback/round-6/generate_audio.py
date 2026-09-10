#!/usr/bin/env python3
"""Heart impact: two short recorded mouth pops, preserving seven selected sounds."""
import importlib.util
import json
import math
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('round5',ROOT.parent/'round-5/generate_audio.py')
r5=importlib.util.module_from_spec(spec); spec.loader.exec_module(r5)
RATE=r5.RATE
SPECS=[
 ('573153',1.0,1.06,.125,.86,'뾲뾲 · 짧고 동그란 입술 팝'),
 ('258269',1.05,1.05,.165,.90,'뾲 뾲 · 조금 더 말랑하고 여유 있게'),
 ('691906',1.05,1.13,.105,.95,'뾲뾲! · 빠르고 또렷한 입술 팝'),
]


def pop(identifier,speed):
    raw=r5.r4.prior.read_wav(ROOT/'sources'/f'mouth-{identifier}.wav')
    peak=max(abs(x) for x in raw)
    first=next(i for i,x in enumerate(raw) if abs(x)>=peak*.03)
    last=len(raw)-next(i for i,x in enumerate(reversed(raw)) if abs(x)>=peak*.03)
    raw=raw[max(0,first-24):min(len(raw),last+round(.006*RATE))]
    result=[]
    for i in range(int((len(raw)-1)/speed)):
        position=i*speed; left=int(position); frac=position-left
        result.append((raw[left]*(1-frac)+raw[left+1]*frac)/peak)
    # Keep each lip release intact, with clean silence between the two pops.
    return r5.finish(result,tail=.008)


def heart(variant):
    source,speed1,speed2,offset,gain,description=SPECS[variant]
    a=pop(source,speed1); b=pop(source,speed2)
    offset=round(offset*RATE)
    assert len(a)+round(.012*RATE)<=offset
    result=[0.0]*(offset+len(b))
    result[:len(a)]=a
    result[offset:]=[x*gain for x in b]
    # Both components already have fades and headroom; avoid distorting the mouth texture.
    return result,[0,offset/RATE],[len(a),len(b)]


def main():
    output=ROOT/'audio'; output.mkdir(exist_ok=True)
    previous=json.loads((ROOT.parent/'round-5/audio-manifest.json').read_text())
    group={'id':'throwable_bouncy_heart','label':'통통 하트','kind':'hit','object_id':'throwable_bouncy_heart',
      'description':'입술을 터뜨리는 뾲뾲. 한 번 맞을 때 짧은 팝 두 번이 납니다.'}
    groups=[group]; sounds=[]
    for variant,entry in enumerate(SPECS):
        values,cues,lengths=heart(variant); option='ABC'[variant]; name='throwable_bouncy_heart-'+option.lower()+'-v6'
        single=output/(name+'.wav'); r5.r4.prior.save_wav(single,values)
        values=r5.r4.prior.read_wav(single)
        repeat=output/(name+'-repeat.wav'); r5.r4.prior.save_wav(repeat,r5.r4.prior.repeated(values,.5))
        sounds.append({'id':name,'group_id':group['id'],'kind':'hit','object_id':group['id'],'label':'통통 하트 '+option,'option':option,
          'description':entry[5],'duration_seconds':len(values)/RATE,'repeat_interval_seconds':.5,
          'file':'audio/'+single.name,'repeat_file':'audio/'+repeat.name,'sha256':r5.r4.prior.sha(single),'repeat_sha256':r5.r4.prior.sha(repeat),
          'approval':'pending','selection':'pending','trigger':'impact','pops_per_impact':2,'pop_onsets_seconds':cues,'pop_frame_counts':lengths,
          'sample_rate':RATE,'channels':1,'bit_depth':16,'source_ids':['mouth-'+entry[0]],
          'processing':'Recorded mouth pop, trimmed and lightly resampled; two non-overlapping releases with linear gain and fades. No oscillator or saturation.',
          'peak_dbfs':round(20*math.log10(max(abs(x) for x in values)),2),
          'rms_dbfs':round(20*math.log10(math.sqrt(sum(x*x for x in values)/len(values))),2)})
    latest={'throwable_squeaky_duck':'B','throwable_toy_cannon':'C'}
    for oldgroup in previous['groups']:
        identifier=oldgroup['id']
        if identifier==group['id']: continue
        selected=[s for s in previous['sounds'] if s['group_id']==identifier and (s['approval']=='approved' or s['option']==latest.get(identifier))]
        assert len(selected)==1
        g={k:v for k,v in oldgroup.items() if not k.startswith('comparison_')}
        g['description']='선택 확정 · 원본 파일과 음량 그대로.'
        groups.append(g)
        item=selected[0].copy(); item['carried_from']='round-5'
        if identifier in latest:
            item.update(approval='approved',selection='chosen_round_5',approval_evidence='사용자: 오리는 b 대포는 c. 파일과 음량을 그대로 확정함.')
        for key in ['file','repeat_file']: shutil.copyfile(ROOT.parent/'round-5'/item[key],ROOT/item[key])
        sounds.append(item)
    values=[0.0]*round(.15*RATE); cues=[]
    for item in sounds[:3]:
        cues.append(len(values)/RATE)
        values+=r5.r4.prior.read_wav(ROOT/item['file'])+[0.0]*round(.65*RATE)
    target=output/'throwable_bouncy_heart-comparison-v6.wav'; r5.r4.prior.save_wav(target,values)
    group.update(comparison_file='audio/'+target.name,comparison_sha256=r5.r4.prior.sha(target),comparison_cues_seconds=cues)
    manifest={'review_round':6,'approval':'pending','groups':groups,'sounds':sounds,'retired_features':['enlargement_sound'],
      'visual_status':'approved_implemented_on_macos_branch','source_manifest':'sources/manifest.json',
      'prior_source_manifest':'../round-4/sources/manifest.json','visual_review':'../round-2/index.html#visual-heading'}
    data=json.dumps(manifest,ensure_ascii=False,indent=2)
    (ROOT/'audio-manifest.json').write_text(data+'\n')
    (ROOT/'review-data.js').write_text('globalThis.sideyAudioCandidates = '+data+';\n')
    print('3 new double mouth-pop hearts + 7 selected originals, 21 WAV files.')

if __name__=='__main__': main()
