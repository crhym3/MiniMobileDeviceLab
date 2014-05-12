# Script for initializing a replica instance:
# - create /apps/bin/update.sh script
# - create /apps/bin/github-push-to-deploy.js
# - update default nginx-backed site configuration
# - update nodejs apps

mkdir -p /apps/bin

cat <<EOF > /apps/bin/update.sh
#!/bin/bash

REPO_URL=https://github.com/crhym3/MiniMobileDeviceLab.git
APP_DIR=/apps/mmdl
DB_URL=$(curl -f -s -H 'Metadata-Flavor: Google' http://metadata/computeMetadata/v1/instance/attributes/MMDL_DB_URL)
DB_NAME=$(curl -f -s -H 'Metadata-Flavor: Google' http://metadata/computeMetadata/v1/instance/attributes/MMDL_DB_NAME)

if [ ! -d \$APP_DIR ]; then
    git clone \$REPO_URL \$APP_DIR
fi

cd \$APP_DIR
git reset --hard && git pull

cd node && npm install
forever stop --plain \$APP_DIR/node/app.js
MMDL_DB_URL=\$DB_URL MMDL_DB_NAME=\$DB_URL forever start --plain \$APP_DIR/node/app.js
EOF

chmod +x /apps/bin/update.sh


cat <<EOF > /apps/bin/github-push-to-deploy.js
#!/usr/bin/env nodejs
var fs = require('fs'),
    proc = require('child_process');

var payload;
try {
    payload = JSON.parse(fs.readFileSync('/dev/stdin'));
} catch(err) {
    process.stdout.write('Status: 400\nContent-Type: text/plain\n\n' + err.toString() + '\n');
    process.exit(0);
}

if (!payload.ref || !payload.ref.match(/^refs\/heads\/master$/i)) {
    process.stdout.write('Status: 200\nContent-Type: text/plain\n\nSkip update: not master branch\n');
    process.exit(0);
}

proc.execFile('sudo', ['-u', 'apps', '/apps/bin/update.sh'], {}, function(err, stdout, stderr) {
    var resp = 'Status: ' + (err ? 500 : 200) + '\nContent-Type: text/plain\n\n';
    resp += '\n>>> STDOUT:\n' stdout + '\n\n>>> STDERR:\n' + stderr;
    process.stdout.write(resp);
});
EOF

chmod +x /apps/bin/github-push-to-deploy.js
echo 'www-data ALL=(ALL) NOPASSWD: /apps/bin/update.sh' >> /etc/sudoers


cat <<EOF > /etc/nginx/sites-enabled/default
server {
    root /apps;
    index index.html index.htm;

    server_name localhost;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /github {
        gzip off;
        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        fastcgi_param SCRIPT_FILENAME \$document_root/bin/github-push-to-deploy.js;
        include fastcgi_params;
    }
}
EOF

service nginx restart
sudo -u apps /apps/bin/update.sh
