#!/usr/bin/env python3
import importlib.util
import json
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('round6',ROOT/'generate_audio.py')
gen=importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)
read=gen.r5.r4.prior.read_wav; sha=gen.r5.r4.prior.sha; RATE=gen.RATE
m=json.loads((ROOT/'audio-manifest.json').read_text())
assert len(m['sounds'])==10 and len(m['groups'])==8
assert len(list((ROOT/'audio').glob('*.wav')))==21
assert sum(s['approval']=='approved' for s in m['sounds'])==7
assert all(s['kind']=='hit' for s in m['sounds'])
assert m['retired_features']==['enlargement_sound']
for s in m['sounds']:
    a=read(ROOT/s['file']); repeat=read(ROOT/s['repeat_file'])
    assert sha(ROOT/s['file'])==s['sha256'] and sha(ROOT/s['repeat_file'])==s['repeat_sha256']
    assert len(a)==round(s['duration_seconds']*RATE)
    assert a[0]==a[-1]==0 and max(abs(x) for x in a)<=10**(-14/20)+1/32767
    assert len(a)/RATE<s['repeat_interval_seconds']
    assert repeat==gen.r5.r4.prior.repeated(a,s['repeat_interval_seconds'])
    if s['approval']=='approved':
        for key in ['file','repeat_file']: assert (ROOT/s[key]).read_bytes()==(ROOT.parent/'round-5'/s[key]).read_bytes()
        if s['object_id']=='throwable_squeaky_duck': assert s['option']=='B' and s['quacks_per_impact']==1
        if s['object_id']=='throwable_toy_cannon': assert s['option']=='C'
    else:
        assert s['object_id']=='throwable_bouncy_heart' and s['pops_per_impact']==2
        expected,cues,lengths=gen.heart('ABC'.index(s['option']))
        assert len(expected)==len(a)
        assert all(abs(x-y)<=.501/32767 for x,y in zip(expected,a))
        assert s['pop_onsets_seconds']==cues and s['pop_frame_counts']==lengths
        gap=a[lengths[0]:round(cues[1]*RATE)]
        assert len(gap)>=round(.012*RATE) and not any(gap)
        print(s['label'],f"{len(a)/RATE:.3f}s",'two mouth pops, gap',round(len(gap)/RATE*1000),'ms')
g=m['groups'][0]; expected=[0.0]*round(.15*RATE); cues=[]
for s in m['sounds'][:3]:
    cues.append(len(expected)/RATE)
    expected+=read(ROOT/s['file'])+[0.0]*round(.65*RATE)
assert read(ROOT/g['comparison_file'])==expected and g['comparison_cues_seconds']==cues
assert sha(ROOT/g['comparison_file'])==g['comparison_sha256']
for source in json.loads((ROOT/'sources/manifest.json').read_text())['sources']:
    assert source['license']=='CC0-1.0'
    for prefix in ['original','decoded']:
        assert sha(ROOT/'sources'/source[prefix+'_file'])==source[prefix+'_sha256']
class References(HTMLParser):
    def handle_starttag(self,tag,attrs):
        for key,value in attrs:
            if key in ['href','src'] and value and not value.startswith(('#','http')):
                assert (ROOT/value.split('#')[0]).is_file(),value
References().feed((ROOT/'index.html').read_text())
assert (ROOT/'review-data.js').read_text()=='globalThis.sideyAudioCandidates = '+json.dumps(m,ensure_ascii=False,indent=2)+';\n'
print('PASS: 3 heart candidates, 7 approved originals, 21 WAVs; PCM, two separate pops, hashes, preservation, repeats/comparison and HTML links.')
