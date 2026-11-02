// Production-only build for the current Render static site.
// Run: npm install && npm run build
const fs = require('node:fs/promises');
const path = require('node:path');
const { minify } = require('html-minifier-terser');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'dist');
// Publish only required public assets, never repository source, backups or migrations.
const publicRoots = new Set(['img','vendor']);
const publicFiles = new Set([
  'manifest.json','favicon.png','apple-touch-icon-v2.png','icon-192.png','icon-192-v2.png','icon-512.png','icon-512-v2.png','icon-maskable-512-v3.png','notif-icon.png','notif-badge.png',
  'sphere-dark-theme.css','sphere-desktop.css','verify-fee-qr.png',
  'terms.html','privacy.html','refund.html','contact.html',
  'robots.txt','sitemap.xml','sw.js','service-worker.js'
]);
async function copyAssets(){
  for(const file of publicFiles){
    const source=path.join(root,file);
    try { if((await fs.stat(source)).isFile()) await fs.copyFile(source,path.join(out,file)); }
    catch(e){ if(e.code!=='ENOENT')throw e; }
  }
  for(const dir of publicRoots){
    const source=path.join(root,dir);
    try { await fs.cp(source,path.join(out,dir),{recursive:true,filter:p=>!/(^|\\/)(\\.git|\\.env|node_modules)(\\/|$)/.test(p)}); }
    catch(e){ if(e.code!=='ENOENT')throw e; }
  }
}
async function main(){
  const original = await fs.readFile(path.join(root, 'index.html.html'),'utf8');
  // No source maps; do not disable browser developer tools or pretend source is secret.
  const html=await minify(original,{
    collapseWhitespace:true,
    conservativeCollapse:true,
    removeComments:true,
    removeOptionalTags:false,
    removeAttributeQuotes:false,
    removeEmptyAttributes:false,
    minifyCSS:true,
    minifyJS:{compress:{defaults:true},mangle:false,format:{comments:false}},
    keepClosingSlash:true,
    caseSensitive:true,
    continueOnParseError:false
  });
  await fs.rm(out,{recursive:true,force:true});
  await fs.mkdir(out,{recursive:true});
  await copyAssets();
  await fs.writeFile(path.join(out,'index.html'),html);
  console.log('Production build:',original.length,'→',html.length,'bytes; no source maps.');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
