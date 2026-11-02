// Production-only build for the current Render static site.
// Run: npm install && npm run build
const fs = require('node:fs/promises');
const path = require('node:path');
const { minify } = require('html-minifier-terser');
const root = path.resolve(__dirname, '..');
const out = path.join(root, 'dist');
async function copyAssets(from, to) {
  for (const entry of await fs.readdir(from, { withFileTypes: true })) {
    if (['.git','node_modules','dist','.github','scripts','supabase','docs'].includes(entry.name)) continue;
    if (from===root && (entry.name==='index.html.html'|| entry.name==='index.html' || entry.name==='package.json'||entry.name==='package-lock.json')) continue;
    const a=path.join(from,entry.name), b=path.join(to,entry.name);
    if(entry.isDirectory()){ await fs.mkdir(b,{recursive:true}); await copyAssets(a,b); }
    else if(entry.isFile()) await fs.copyFile(a,b);
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
  await copyAssets(root,out);
  await fs.writeFile(path.join(out,'index.html'),html);
  console.log('Production build:',original.length,'→',html.length,'bytes; no source maps.');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
