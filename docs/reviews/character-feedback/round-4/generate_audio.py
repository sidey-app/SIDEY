#!/usr/bin/env python3
"""Impact-first review edits of CC0 samples; never linked to application resources."""
import array
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import shutil
import sys
import wave

ROOT = Path(__file__).resolve().parent
RATE = 48000
spec = importlib.util.spec_from_file_location('round3', ROOT.parent / 'round-3/generate_audio.py')
prior = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prior)
USED = set()

GROUPS = [
 ('throwable_squeaky_duck', '삑삑 오리', '고무 삑 소리 대신, 맞자마자 오리의 꽥꽥.', ['꽥꽥 · 기본 오리, 두 번째는 가볍게', '꽥꽥! · 조금 높고 빠른 오리', '꽥—꽥 · 원음에 가까운 넉넉한 울음']),
 ('throwable_toy_cannon', '미니 대포', '대포알이 닿는 순간 펑. 짧은 폭발과 잔향만 비교합니다.', ['펑! · 짧고 선명한 폭발', '펑— · 낮은 울림이 붙는 폭발', '팡! · 빠르고 밝은 폭발']),
 ('patch_soft_ball', '말랑공', '충돌이 먼저 느껴지는 말랑한 타격. 기존 C도 이번 재작업에서 새 후보로 대체합니다.', ['뽁 · 가벼운 말랑공', '팍 · 탄탄한 고무공', '퐁 · 속이 빈 부드러운 공']),
 ('mini_paprika', '미니 파프리카', '작은 채소가 콕 부딪히는 짧은 타격.', ['톡 · 작고 단단한 접촉', '탁 · 조금 더 바삭한 접촉', '똑 · 둥근 속울림']),
 ('banana', '바나나', '말랑한 물체가 몸에 찰싹 닿는 느낌.', ['찹 · 짧고 부드러운 접촉', '찰싹 · 납작하고 찰진 접촉', '퍽 · 더 묵직한 바나나']),
 ('dust_bath_pouch', '먼지목욕 모래주머니', '천 주머니의 퍽 뒤에 짧은 모래 질감.', ['푹 · 폭신한 주머니', '푸석 · 모래 입자가 더 또렷하게', '퍽 · 묵직하고 짧은 주머니']),
 ('starlight_orb', '별빛 구슬', '구슬이 닿는 똑 소리와 같은 순간에 울리는 한 번의 공명.', ['똑 · 작은 유리 구슬', '땡 · 맑고 짧은 반짝임', '통 · 따뜻한 구슬 울림']),
 ('throwable_bouncy_heart', '통통 하트', '두근거리는 멜로디 대신 젤리가 맞는 뽁 소리.', ['뽁 · 부드러운 젤리', '땁 · 찰진 젤리', '퐁 · 둥글고 두툼한 젤리']),
]


def source(name, speed=1.0, limit=None, lowpass=None):
    USED.add(name)
    with wave.open(str(ROOT / 'sources' / f'{name}.wav')) as wav:
        assert (wav.getframerate(), wav.getnchannels(), wav.getsampwidth()) == (RATE, 1, 2)
        raw = array.array('h', wav.readframes(wav.getnframes()))
    if sys.byteorder != 'little': raw.byteswap()
    peak = max(abs(x) for x in raw)
    start = next(i for i,x in enumerate(raw) if abs(x) >= peak*.025)
    end = len(raw)-next(i for i,x in enumerate(reversed(raw)) if abs(x) >= peak*.015)
    raw = raw[max(0,start-24):end]
    size = int((len(raw)-1)/speed)
    if limit: size = min(size,round(limit*RATE))
    values=[]
    for i in range(size):
        position=i*speed; left=int(position); frac=position-left
        values.append((raw[left]*(1-frac)+raw[left+1]*frac)/peak)
    if lowpass:
        alpha=1-math.exp(-2*math.pi*lowpass/RATE); state=0
        for i,x in enumerate(values):
            state+=alpha*(x-state); values[i]=state
    for i in range(len(values)):
        values[i] *= min(1, i/(RATE*.0004)) * min(1, (len(values)-1-i)/(RATE*.006))
    return values


def mix(layers, duration):
    output=[0.0]*round(duration*RATE)
    for values,gain,offset in layers:
        offset=round(offset*RATE)
        for i,x in enumerate(values[:max(0,len(output)-offset)]): output[offset+i]+=gain*x
    return output


def resonance(hz,duration,decay):
    return [math.sin(2*math.pi*hz*i/RATE)*math.exp(-decay*i/RATE) for i in range(round(duration*RATE))]


def finish(values):
    # Preserve the impact envelope; soft saturation only controls isolated sample peaks.
    mean=sum(values)/len(values)
    values=[math.tanh((x-mean)*1.4) for x in values]
    for i in range(len(values)):
        values[i]*=min(1,i/(RATE*.0006))*min(1,(len(values)-1-i)/(RATE*.018))
    rms=math.sqrt(sum(x*x for x in values)/len(values))
    gain=min(.067/rms,10**(-14/20)/max(abs(x) for x in values))
    return [x*gain for x in values]


def hit(identifier,v):
    if identifier=='throwable_squeaky_duck':
        a=source('duck',speed=[1.12,1.28,1.0][v])
        second=len(a)/RATE+[.026,.018,.050][v]
        duration=second+len(a)/RATE
        values=mix([(a,1,0),(a,[.82,.93,.75][v],second)],duration)
    elif identifier=='throwable_toy_cannon':
        duration=[.32,.44,.27][v]
        if v==0: layers=[(source('explosion',1.15,limit=duration),1,0)]
        elif v==1: layers=[(source('cannon',1.10,limit=duration,lowpass=2600),1,0),(source('explosion',.95,limit=duration),.32,0)]
        else: layers=[(source('explosion',1.55,limit=duration),1,0),(source('impactGeneric_light_002'),.13,0)]
        values=mix(layers,duration)
    else:
        definitions={
         'patch_soft_ball': [(.17,'impactSoft_medium_000',1.16,420,.30,38),(.16,'impactPunch_medium_001',1.28,510,.17,45),(.21,'impactSoft_medium_002',.93,345,.48,27)],
         'mini_paprika': [(.12,'impactWood_light_000',1.30,860,.05,70),(.13,'impactGeneric_light_001',1.06,720,.12,50),(.16,'impactWood_light_002',.91,540,.30,35)],
         'banana': [(.18,'impactSoft_heavy_000',1.4,280,.12,32),(.19,'impactPunch_medium_000',1.1,0,0,1),(.22,'impactSoft_heavy_002',.95,210,.14,25)],
         'dust_bath_pouch': [(.24,'impactSoft_heavy_001',1.0,0,0,1),(.25,'footstep_snow_001',1.1,0,0,1),(.18,'impactSoft_heavy_003',1.35,0,0,1)],
         'starlight_orb': [(.20,'impactGlass_light_000',1.0,1320,.08,24),(.28,'impactGlass_light_002',1.13,1568,.23,17),(.25,'impactGlass_light_004',.81,880,.35,19)],
         'throwable_bouncy_heart': [(.19,'impactSoft_medium_001',1.26,610,.40,32),(.16,'impactPunch_medium_002',1.45,740,.15,45),(.23,'impactSoft_medium_003',.89,460,.50,23)],
        }
        duration,name,speed,hz,gain,decay=definitions[identifier][v]
        layers=[(source(name,speed,limit=duration),1,0)]
        if hz: layers.append((resonance(hz,duration,decay),gain,0))
        if identifier=='dust_bath_pouch':
            extra='impactSoft_medium_004' if v==1 else 'footstep_snow_000'
            layers.append((source(extra,1.1,limit=duration),.42 if v==1 else .20,0))
        values=mix(layers,duration)
    return finish(values)


def main():
    output=ROOT/'audio'; output.mkdir(exist_ok=True)
    sounds=[]; groups=[]
    previous=json.loads((ROOT.parent/'round-3/audio-manifest.json').read_text())
    for identifier,label,description,choices in GROUPS:
        group={'id':identifier,'label':label,'description':description,'kind':'hit','object_id':identifier}
        for v,description in enumerate(choices):
            before=USED.copy(); USED.clear()
            samples=hit(identifier,v); dependencies=sorted(USED); USED.update(before)
            option='ABC'[v]; name=f'{identifier}-{option.lower()}-v4'
            single=output/f'{name}.wav'; prior.save_wav(single,samples)
            samples=prior.read_wav(single)
            interval=.9 if identifier=='throwable_squeaky_duck' else .5
            repeat=output/f'{name}-repeat.wav'; prior.save_wav(repeat,prior.repeated(samples,interval))
            sounds.append({'id':name,'group_id':identifier,'kind':'hit','object_id':identifier,'label':f'{label} {option}','option':option,'description':description,
              'file':f'audio/{single.name}','repeat_file':f'audio/{repeat.name}','sha256':prior.sha(single),'repeat_sha256':prior.sha(repeat),
              'duration_seconds':len(samples)/RATE,'repeat_interval_seconds':interval,'approval':'pending','selection':'pending',
              'trigger':'impact','sample_rate':RATE,'channels':1,'bit_depth':16,'source_ids':dependencies,
              'peak_dbfs':round(20*math.log10(max(abs(x) for x in samples)),2),
              'rms_dbfs':round(20*math.log10(math.sqrt(sum(x*x for x in samples)/len(samples))),2),
              'provenance':'Edited CC0 sample; source files, authors and URLs in sources/manifest.json. Resonance layers are original fixed-frequency synthesis.'})
        groups.append(group)
    grow=next(g for g in previous['groups'] if g['id']=='grow').copy()
    grow['description']='3차 C 기반 3안을 파일·음량 그대로 가져왔습니다. 피격음과 별도로 골라 주세요.'
    groups.append(grow)
    for item in previous['sounds']:
        if item['kind']!='grow': continue
        item=item.copy(); item['trigger']='enlarge'; item['carried_from']='round-3'; item['source_ids']=[]
        for key in ['file','repeat_file']: shutil.copyfile(ROOT.parent/'round-3'/item[key],ROOT/item[key])
        sounds.append(item)
    for group in groups:
        sequence=[0.0]*round(.15*RATE); cues=[]
        for item in [s for s in sounds if s['group_id']==group['id']]:
            cues.append(len(sequence)/RATE)
            sequence+=prior.read_wav(ROOT/item['file'])+[0.0]*round(.55*RATE)
        target=output/f"{group['id']}-comparison-v4.wav"; prior.save_wav(target,sequence)
        group.update(comparison_file=f'audio/{target.name}',comparison_sha256=prior.sha(target),comparison_cues_seconds=cues)
    manifest={'review_round':4,'approval':'pending','groups':groups,'sounds':sounds,'visual_review':'../round-2/index.html#visual-heading','visual_status':'unchanged_pending_approval','source_manifest':'sources/manifest.json'}
    data=json.dumps(manifest,ensure_ascii=False,indent=2)
    (ROOT/'audio-manifest.json').write_text(data+'\n')
    (ROOT/'review-data.js').write_text('globalThis.sideyAudioCandidates = '+data+';\n')
    print(f'Created 24 new impact candidates + 3 unchanged growth candidates; {len(USED)} source samples.')

if __name__=='__main__': main()
