import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const html=fs.readFileSync('index.html.html','utf8');
const stateStart=html.indexOf('function adminEditorProfileState(');
const stateEnd=html.indexOf('\n function adminEditorProfileShortcut()',stateStart);
assert.ok(stateStart>0 && stateEnd>stateStart, 'profile state helper exists');
const stateFn=Function(html.slice(stateStart,stateEnd)+'; return adminEditorProfileState;')();

test('profile completeness uses bio + skills + sample/video/portfolio, not verification',()=>{
  const full={id:'editor1',bio:'  Video editor  ',skills:['  ','reels'],portfolio_url:'https://example.com/work'};
  assert.equal(stateFn(full,new Set()),'complete');
  assert.equal(stateFn({...full,is_verified:false},new Set()),'complete');
  assert.equal(stateFn({...full,is_verified:true},new Set()),'complete');
  assert.equal(stateFn({id:'editor2',bio:'intro',skills:[''],portfolio_url:''},new Set()),'partial');
  assert.equal(stateFn({id:'editor3',bio:' ',skills:[' ',''],sample_video_url:' '},new Set()),'incomplete');
  assert.equal(stateFn({id:'editor4',bio:'about',skills:['video'],portfolio_url:'',sample_video_url:''},new Set(['editor4'])),'complete');
  assert.equal(stateFn({id:'editor5',bio:'about',skills:['video'],sample_video_url:'https://example.com/sample'},new Set()),'complete');
});

test('separate completeness and verification choices combine as an AND filter',()=>{
  const start=html.indexOf('function adminUserSetProfileFilter(');
  const end=html.indexOf('\n async function adminUsersTab()',start);
  assert.ok(start>0 && end>start,'filter callbacks exist');
  const cards=[
    {dataset:{profile:'complete',verified:'yes'},style:{}},
    {dataset:{profile:'partial',verified:'yes'},style:{}},
    {dataset:{profile:'partial',verified:'no'},style:{}},
    {dataset:{profile:'incomplete',verified:'no'},style:{}}
  ];
  const chip=(kind,value)=>({
    dataset:{filterKind:kind,filterValue:value},classList:{toggle(){}},setAttribute(){}
  });
  const buttons=[
    ...['all','complete','partial','incomplete'].map(v=>chip('completion',v)),
    ...['all','verified','unverified'].map(v=>chip('verification',v))
  ];
  const summary={textContent:''};
  const empty={hidden:false};
  const root={querySelectorAll:()=>buttons};
  const document={
    getElementById(id){return ({auEditorFilters:root,auShowing:summary,auNoUsers:empty})[id]||null;},
    querySelectorAll(){return cards;}
  };
  const state=Function('document',`let adminUserCompletion='all',adminUserVerification='all';\n${html.slice(start,end)}\nreturn {set:adminUserSetProfileFilter,apply:adminUserApplyProfileFilters};`)(document);
  state.set('completion','partial');
  assert.deepEqual(cards.map(x=>x.style.display),['none','','','none']);
  state.set('verification','verified');
  assert.deepEqual(cards.map(x=>x.style.display),['none','','none','none']);
  assert.match(summary.textContent,/Showing 1 of 4/);
  state.set('verification','unverified');
  assert.deepEqual(cards.map(x=>x.style.display),['none','none','','none']);
  state.set('completion','all');
  assert.deepEqual(cards.map(x=>x.style.display),['none','none','','']);
  state.set('verification','all');
  assert.deepEqual(cards.map(x=>x.style.display),['','','','']);
});

test('both mobile and PC verification desks offer the dedicated editor profiles view',()=>{
  const pc=html.slice(html.indexOf('async function pcVerificationTab(){'),html.indexOf('function pcvTime('));
  const phone=html.slice(html.indexOf('async function adminVerificationTab(){'),html.indexOf('// ---- 5) Moderation'));
  assert.match(pc,/adminEditorProfileShortcut\(\)/);
  assert.match(phone,/adminEditorProfileShortcut\(\)/);
  assert.match(html,/adminUserRole='EDITOR'/);
});
