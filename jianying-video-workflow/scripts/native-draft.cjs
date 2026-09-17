#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');

function validate(d) {
  assert(d && typeof d === 'object' && !Array.isArray(d), 'Draft must be an object');
  assert(Array.isArray(d.tracks), 'Draft tracks missing');
  let end = 0;
  for (const track of d.tracks) for (const seg of track.segments || []) {
    const r = seg.target_timerange;
    assert(r && Number.isSafeInteger(r.start) && r.start >= 0 &&
      Number.isSafeInteger(r.duration) && r.duration > 0, 'Invalid segment time range');
    end = Math.max(end, r.start + r.duration);
  }
  assert(end > 0 && d.duration === end, 'Draft duration must equal final segment end');
  for (const key of ['width', 'height']) assert(d.canvas_config?.[key] > 0, 'Invalid canvas');
  for (const kind of ['videos', 'audios']) for (const m of d.materials?.[kind] || []) {
    assert(typeof m.path === 'string' && path.isAbsolute(m.path) && fs.existsSync(m.path),
      `Missing or nonabsolute ${kind} material: ${m.path}`);
  }
  return d;
}
function summary(d) {
  return {id:d.id, duration:d.duration || 0, canvas:d.canvas_config,
    tracks:(d.tracks || []).map(t => ({type:t.type, name:t.name, segments:(t.segments || []).length}))};
}
function appStopped(app) {
  const processes = execFileSync('ps', ['-axo', 'comm='], {encoding:'utf8'});
  assert(!processes.split('\n').some(p => p.trim().startsWith(app + '/Contents/MacOS/')),
    'Save work and quit Jianying before apply; the running editor can overwrite external changes');
}
async function main() {
  const [mode, arg, target] = process.argv.slice(2);
  if (mode === 'self-test') {
    const d = {duration:10, canvas_config:{width:1920,height:1080}, materials:{},
      tracks:[{type:'video',segments:[{target_timerange:{start:0,duration:10}}]}]};
    validate(d);
    assert.throws(() => validate({...d,duration:11}));
    assert.throws(() => validate({...d,materials:{videos:[{path:'/missing-video-test.mp4'}]}}));
    console.log('PASS: timing and missing-media guards'); return;
  }
  assert(['inspect','apply','roundtrip'].includes(mode) && arg,
    'Usage: native-draft.cjs inspect PROJECT | apply SOURCE_JSON BLANK_PROJECT | roundtrip EXISTING_TEST_DIRECTORY | self-test');
  const app = fs.realpathSync(process.env.JIANYING_APP || '/Applications/VideoFusion-macOS.app');
  const root = fs.realpathSync(mode === 'apply' ? target : arg);
  let source;
  if (mode === 'apply') {
    appStopped(app);
    source = validate(JSON.parse(fs.readFileSync(arg, 'utf8')));
  }
  const a = require(path.join(app, 'Contents/Frameworks/videoeditor_addon.node'));
  const init = a.initialize('{}');
  assert(JSON.parse(init).admissible === true, 'Native module unavailable');
  let n = 0, session;
  async function call(req) {
    const r = JSON.parse(await a.invoke(JSON.stringify({id:String(++n),priority:'interactive',protocolVersion:1,...req})));
    assert(r.accepted !== false, `${req.operation || req.method}: ${JSON.stringify(r)}`);
    return r;
  }
  const io = (operation, file, content) => call({domain:'draft',operation,
    params:{rootPath:root,path:path.join(root,file),...(content === undefined ? {} : {content})}});
  const read = async file => {
    const r = await io('readFile',file);
    assert(r.exists !== false && typeof r.content === 'string', `Missing ${file}`);
    return {data:JSON.parse(r.content),cipher:r.cipherType};
  };
  try {
    if (mode === 'roundtrip') {
      // Only write a unique test file; never reuse or overwrite a project file.
      const file = `native-roundtrip-${Date.now()}.json`;
      assert(!fs.existsSync(path.join(root,file)));
      const input = {id:'roundtrip',version:360000,tracks:[],materials:{},duration:0};
      await io('writeFile',file,JSON.stringify(input));
      const result = await read(file);
      assert.deepEqual(result.data,input);
      console.log(JSON.stringify({passed:true,file:path.join(root,file),cipher:result.cipher}));
      return;
    }
    const current = await read('draft_content.json');
    if (mode === 'inspect') {
      console.log(JSON.stringify({project:root,cipher:current.cipher,...summary(current.data)},null,2)); return;
    }
    const project = JSON.parse(fs.readFileSync(path.join(root,'Timelines/project.json'),'utf8'));
    const id = project.main_timeline_id;
    assert(typeof id === 'string' && /^[A-Za-z0-9-]+$/.test(id), 'Invalid native timeline ID');
    assert(project.timelines.length === 1 && project.timelines[0].id === id, 'Use a dedicated single-timeline blank project');
    const timeline = `Timelines/${id}`;
    const existing = await read(`${timeline}/draft_content.json`);
    for (const d of [current.data, existing.data])
      assert(!(d.tracks || []).some(t => (t.segments || []).length), 'Target must be a new blank project');
    const meta = (await read('draft_meta_info.json')).data;
    const backup = `${root}.before-native-${Date.now()}`;
    assert(!fs.existsSync(backup));
    fs.cpSync(root, backup, {recursive:true,errorOnExist:true,force:false});
    console.log(JSON.stringify({backup}));
    session = (await call({method:'create',params:{kind:'draft'}})).sessionId;
    assert(session, 'Missing native session');
    await call({method:'load',sessionId:session,params:{draftJson:JSON.stringify(current.data),workspacePath:root}});
    const r = await call({domain:'edit',operation:'draft.setDraft',targetId:session,params:{draftSnapshot:source}});
    const converted = validate(r.draftSnapshot);
    assert.deepEqual(summary(converted).tracks,summary(source).tracks, 'Native conversion changed track structure');
    assert.equal(converted.duration,source.duration);
    Object.assign(converted,{id,path:root,platform:current.data.platform,
      last_modified_platform:current.data.last_modified_platform,
      new_version:current.data.new_version,version:current.data.version});
    const content = JSON.stringify(converted);
    appStopped(app);
    for (const file of ['draft_content.json','template-2.tmp',`${timeline}/draft_content.json`,`${timeline}/template-2.tmp`]) {
      await io('writeFile',file,content);
      assert.deepEqual((await read(file)).data,converted, `Readback failed: ${file}; backup: ${backup}`);
    }
    Object.assign(meta,{tm_duration:converted.duration,tm_draft_modified:Date.now()*1000});
    await io('writeFile','draft_meta_info.json',JSON.stringify(meta));
    assert.equal((await read('draft_meta_info.json')).data.tm_duration,converted.duration);
    console.log(JSON.stringify({project:root,backup,...summary(converted),
      next:'Open in Jianying, visually inspect text and picture, audition audio, save/reopen and export.'},null,2));
  } finally {
    if (session) await call({method:'destroy',sessionId:session});
    if (a.shutdown) await a.shutdown();
  }
}
main().catch(e => {console.error(e.message); process.exitCode = 1;});
