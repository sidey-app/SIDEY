#!/usr/bin/env python3
import importlib.util
import json
from html.parser import HTMLParser
from pathlib import Path
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('round7',ROOT/'generate_audio.py')
gen=importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)
read=gen.io.read_wav; sha=gen.io.sha; RATE=gen.RATE
m=json.loads((ROOT/'audio-manifest.json').read_text())
old=json.loads((ROOT.parent/'round-6/audio-manifest.json').read_text())
assert len(m['sounds'])==13 and len(m['groups'])==9
assert len(list((ROOT/'audio').glob('*.wav')))==28
assert sum(s['approval']=='approved' for s in m['sounds'])==7
assert m['retired_features']==['enlargement_sound']
for s in m['sounds']:
    a=read(ROOT/s['file'])
    assert len(a)==round(s['duration_seconds']*RATE)
    assert a[0]==a[-1]==0 and max(abs(x) for x in a)<=10**(-14/20)+1/32767
    assert sha(ROOT/s['file'])==s['sha256'] and sha(ROOT/s['repeat_file'])==s['repeat_sha256']
    assert read(ROOT/s['repeat_file'])==gen.io.repeated(a,s['repeat_interval_seconds'])
    assert len(a)/RATE<s['repeat_interval_seconds']
    if s['approval']=='approved':
        for key in ['file','repeat_file']: assert (ROOT/s[key]).read_bytes()==(ROOT.parent/'round-6'/s[key]).read_bytes()
    elif s['kind']=='hit':
        assert s['pops_per_impact']==1 and s['events_per_sample']==1
        previous=next(x for x in old['sounds'] if x['group_id']=='throwable_bouncy_heart' and x['option']==s['option'])
        assert a==read(ROOT.parent/'round-6'/previous['file'])[:previous['pop_frame_counts'][0]]
        print(s['label'],f'{len(a)/RATE:.3f}s','exactly V6 first pop; no second pop')
    else:
        assert s['kind']=='chat' and s['trigger']=='chat_bubble_appeared' and s['events_per_sample']==1
        expected=gen.chat('ABC'.index(s['option']))
        assert len(expected)==len(a) and all(abs(x-y)<=.501/32767 for x,y in zip(expected,a))
        print(s['label'],f'{len(a)/RATE:.3f}s',s['description'])
for g in m['groups']:
    if 'comparison_file' not in g: continue
    expected=[0.0]*round(.15*RATE); cues=[]
    for s in m['sounds']:
        if s['group_id']==g['id']:
            cues.append(len(expected)/RATE)
            expected+=read(ROOT/s['file'])+[0.0]*round(.65*RATE)
    assert read(ROOT/g['comparison_file'])==expected and g['comparison_cues_seconds']==cues
    assert sha(ROOT/g['comparison_file'])==g['comparison_sha256']
class References(HTMLParser):
    def handle_starttag(self,tag,attrs):
        for key,value in attrs:
            if key in ['href','src'] and value and not value.startswith(('#','http')):
                assert (ROOT/value.split('#')[0]).is_file(),value
References().feed((ROOT/'index.html').read_text())
assert (ROOT/'review-data.js').read_text()=='globalThis.sideyAudioCandidates = '+json.dumps(m,ensure_ascii=False,indent=2)+';\n'
print('PASS: single-pop heart correction, 3 chat variants, 7 approved originals, 28 WAVs, PCM, hashes, repetitions and links.')
