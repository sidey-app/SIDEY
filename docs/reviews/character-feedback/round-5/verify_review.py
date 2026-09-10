#!/usr/bin/env python3
"""Validate review PCM, approvals, source preservation and cancellation scope."""
import importlib.util
import json
import math
from pathlib import Path
from html.parser import HTMLParser
import array
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('round5',ROOT/'generate_audio.py')
gen=importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)
RATE=gen.RATE
m=json.loads((ROOT/'audio-manifest.json').read_text())
assert m['review_round']==5 and m['retired_features']==['enlargement_sound']
assert len(m['sounds'])==14 and len(m['groups'])==8
assert len(list((ROOT/'audio').glob('*.wav')))==31
assert all(s['kind']=='hit' for s in m['sounds'])
assert not any('grow' in p.name for p in (ROOT/'audio').iterdir())
assert sum(s['approval']=='approved' for s in m['sounds'])==5
for item in m['sounds']:
    single=ROOT/item['file']; repeat=ROOT/item['repeat_file']
    assert gen.r4.prior.sha(single)==item['sha256']
    assert gen.r4.prior.sha(repeat)==item['repeat_sha256']
    samples=gen.r4.prior.read_wav(single)
    assert abs(len(samples)/RATE-item['duration_seconds'])<1/RATE
    assert samples[0]==samples[-1]==0
    assert max(abs(x) for x in samples)<=10**(-14/20)+1/32767
    assert abs(sum(samples)/len(samples))<.003
    assert item['duration_seconds']<item['repeat_interval_seconds']
    expected=gen.r4.prior.repeated(samples,item['repeat_interval_seconds'])
    assert gen.r4.prior.read_wav(repeat)==expected
    if item.get('carried_from'):
        for key in ['file','repeat_file']:
            assert (ROOT/item[key]).read_bytes()==(ROOT.parent/'round-4'/item[key]).read_bytes()
        if item['group_id'] in gen.SELECTED:
            assert item['option']==gen.SELECTED[item['group_id']]
            assert item['selection']=='chosen_round_4' and item['approval']=='approved'
        else:
            assert item['group_id']=='throwable_bouncy_heart' and item['approval']=='pending'
    else:
        variant='ABC'.index(item['option'])
        make=gen.duck if item['group_id']=='throwable_squeaky_duck' else gen.cannon
        expected=make(variant)
        assert all(abs(a-b)<=.501/32767 for a,b in zip(samples,expected))
        if make==gen.duck:
            assert item['quacks_per_impact']==1
            assert len(samples)==len(gen.r4.source('duck',speed=[1,1.15,.92][variant]))
        else:
            # The source of gritty high-frequency energy is materially reduced.
            lp=gen.lowpass(samples,3000)
            high=sum((x-y)**2 for x,y in zip(samples,lp))/sum(x*x for x in samples)
            assert high<.12,(item['id'],high)
            print(item['label'],f"{item['duration_seconds']:.2f}s",'high-frequency residual',round(high,4))
for group in m['groups']:
    if 'comparison_file' not in group: continue
    expected=[0.0]*round(.15*RATE); cues=[]
    for s in m['sounds']:
        if s['group_id']==group['id']:
            cues.append(len(expected)/RATE)
            expected+=gen.r4.prior.read_wav(ROOT/s['file'])+[0.0]*round(.65*RATE)
    assert gen.r4.prior.read_wav(ROOT/group['comparison_file'])==expected
    assert group['comparison_cues_seconds']==cues
    assert gen.r4.prior.sha(ROOT/group['comparison_file'])==group['comparison_sha256']
class References(HTMLParser):
    def handle_starttag(self,tag,attrs):
        for key,value in attrs:
            if key in ['href','src'] and value and not value.startswith(('#','http')):
                assert (ROOT/value.split('#')[0]).is_file(),value
References().feed((ROOT/'index.html').read_text())
assert (ROOT/'review-data.js').read_text()=='globalThis.sideyAudioCandidates = '+json.dumps(m,ensure_ascii=False,indent=2)+';\n'
print('PASS: 6 new candidates, 5 approved originals, 3 unchanged heart candidates, 31 WAVs, no growth sound; hashes, levels, repeats, comparisons, single quacks and HTML references.')
