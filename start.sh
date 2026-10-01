#!/usr/bin/env bash
# Serve the built static site in PROJECT_DIR in the foreground.
# Writes $OPENCODE_WEB_DIR/deployment-output.json so the controller can deploy it.
set -euo pipefail

time -p cd "$(dirname "$0")"
/usr/bin/time -p printf 'start: dir=%s\n' "$PWD"

/usr/bin/time -p test -f dist/index.html
PORT="${PORT:-3000}"
/usr/bin/time -p printf 'start: port=%s dist=%s/index.html\n' "$PORT" "$PWD/dist"

# Install dependencies and build only when the project declares them.
if /usr/bin/time -p test -f package.json; then
  if /usr/bin/time -p test -f package-lock.json; then
    /usr/bin/time -p npm ci --no-audit --no-fund
  else
    /usr/bin/time -p npm install --no-audit --no-fund
  fi
  if /usr/bin/time -p node -e "process.exit(JSON.parse(require('fs').readFileSync('package.json','utf8')).scripts?.build?0:1)"; then
    /usr/bin/time -p npm run build
    /usr/bin/time -p test -f dist/index.html
  fi
fi

# Publish the built static directory for the deployment controller.
/usr/bin/time -p node -e "
const fs=require('fs'),path=require('path');
const out=process.env.OPENCODE_WEB_DIR+'/deployment-output.json';
fs.writeFileSync(out,JSON.stringify({project:process.cwd(),directory:path.resolve('dist')}));
console.log('deployment-output:',fs.readFileSync(out,'utf8'));
"
/usr/bin/time -p cat "${OPENCODE_WEB_DIR:?}/deployment-output.json"

# Foreground static server (controller reuses this tmux app-server while healthy).
exec /usr/bin/time -p node -e "
const http=require('http'),fs=require('fs'),path=require('path');
const root=path.resolve('dist');
const mime={'.html':'text/html','.js':'application/javascript','.css':'text/css','.json':'application/json','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.webp':'image/webp','.wasm':'application/wasm'};
http.createServer((req,res)=>{
  try{
    const p=new URL(req.url,'http://x').pathname;
    let f=path.resolve(root,'.'+decodeURIComponent(p));
    if(f!==root&&!f.startsWith(root+'/')){res.writeHead(404);res.end();return;}
    if(fs.statSync(f).isDirectory())f=path.join(f,'index.html');
    res.setHeader('Content-Type',mime[path.extname(f)]||'application/octet-stream');
    res.setHeader('Cache-Control','no-cache');
    res.end(fs.readFileSync(f));
  }catch{res.writeHead(404);res.end('Not found');}
}).listen(Number(process.env.PORT||3000),'0.0.0.0',()=>console.log('serving '+root+' on '+(process.env.PORT||3000)));
"
