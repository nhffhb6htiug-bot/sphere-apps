// in-page mock of the Supabase client for chat tests (synthetic data only)
window.__msgs = []; window.__inserts = []; window.__uploads = 0; window.__failUpload = 0; window.__failInsert = 0; window.__bc = [];
const ME = 'me-111', OTHER = 'other-222';
currentUser = { id: ME, name: 'Hh Client', role: 'CLIENT', baseRole: 'CLIENT' };
window.__q = []; window.__hidden = [];
function qb(table){
  const st = { table, op: 'select', payload: null, single: false, calls: [] }; window.__q.push(st);
  const run = () => {
    if(table === 'sp_messages'){
      if(st.op === 'insert'){
        if(window.__failInsert > 0){ window.__failInsert--; return { data: null, error: { message: 'network down' } }; }
        const row = Object.assign({ id: 'm' + (window.__msgs.length + 1) + '-' + Math.random().toString(36).slice(2, 6), created_at: new Date().toISOString(), mod_status: 'ok' }, st.payload);
        window.__msgs.push(row); window.__inserts.push(row); return { data: st.single ? row : [row], error: null };
      }
      if(st.op === 'update') return { data: null, error: null };
      return { data: st.single ? (window.__msgs[0] || null) : window.__msgs.slice(), error: null };
    }
    if(table === 'sp_msg_hidden'){
      if(st.op === 'insert'){ window.__hidden.push(st.payload.message_id); return { data: null, error: null }; }
      return { data: window.__hidden.map(id => ({ message_id: id })), error: null };
    }
    if(table === 'sp_notifications'){
      if(st.op === 'update') return { data: null, error: null };
      return { data: (window.__notifs || []).slice(), error: null, count: (window.__notifs || []).filter(n => !n.is_read).length };
    }
    if(table === 'profiles') return { data: st.single ? { id: OTHER, full_name: 'Yhiyhi 681', role: 'CLIENT' } : [{ id: OTHER, full_name: 'Yhiyhi 681', role: 'CLIENT' }], error: null };
    return { data: st.single ? null : [], error: null };
  };
  const p = new Proxy(function(){}, { get(t, prop){
    if(prop === 'then') return (res, rej) => Promise.resolve(run()).then(res, rej);
    if(prop === 'insert') return (v) => { st.op = 'insert'; st.payload = v; return p; };
    if(prop === 'update') return (v) => { st.op = 'update'; st.payload = v; return p; };
    if(prop === 'single' || prop === 'maybeSingle') return () => { st.single = true; return p; };
    return (...a) => { st.calls.push([prop, JSON.stringify(a)]); return p; };
  } });
  return p;
}
sb.from = qb;
window.__rpcs = [];
sb.rpc = async (fn, args) => {
  window.__rpcs.push(fn);
  if(fn === 'sp_last_seen') return { data: { visible: true, last_seen_at: new Date(Date.now() - 5 * 60000).toISOString() }, error: null };
  if(fn === 'sp_my_show_last_seen') return { data: true, error: null };
  if(fn === 'sp_profiles_public' || fn === 'sp_public_profiles_by_ids') return { data: [{ id: OTHER, full_name: 'Yhiyhi 681', name: 'Yhiyhi 681', role: 'CLIENT' }], error: null };
  return { data: null, error: null };
};
sb.storage.from = () => ({ upload: async () => { window.__uploads++; if(window.__failUpload > 0){ window.__failUpload--; return { error: { message: 'storage error' } }; } return { error: null }; },
  getPublicUrl: (p) => ({ data: { publicUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' } }),
  createSignedUrls: async (paths) => ({ data: paths.map(p => ({ path: p, signedUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' })), error: null }) });
sb.auth.getSession = async () => ({ data: { session: { access_token: 'test' } } });
sb.channel = (name, opts) => { const h = {}; const ch = { name,
  on(t, f, cb){ (h[f.event] = h[f.event] || []).push(cb); return ch; },
  subscribe(cb){ setTimeout(() => cb && cb('SUBSCRIBED'), 5); return ch; },
  presenceState(){ return window.__pstate || {}; }, track(){ return Promise.resolve(); }, untrack(){ return Promise.resolve(); },
  send(m){ window.__bc.push(m); return Promise.resolve('ok'); }, fire(ev, payload){ (h[ev] || []).forEach(f => f(payload)); } }; (window.__chs = window.__chs || []).push(name); if(String(name).startsWith('presence-')) window.__ch = ch; return ch; };
sb.removeChannel = () => {};
window.notify = () => {}; window.contactCheck = () => {};
currentChatWith = OTHER; currentChatJob = null;
