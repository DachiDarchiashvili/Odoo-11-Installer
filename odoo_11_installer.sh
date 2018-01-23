#!/bin/bash
###################################################################################
# Script for installing Odoo 11 CE
#
# Author: Dachi Darchiashvili
#
# args:
#     -dev true : won't create odoo user and will install odoo on current directory
#
# how to run:
#     sudo bash odoo_11_server_install.sh
###################################################################################

# Capture arguments
while getopts dev: option
do
    case "${option}"
    in
        d) developer=${OPTARG};;
    esac
done

create_odoo_user () {
    echo "Creating odoo user"
    adduser --system --shell=/bin/bash --home=/home/odoo -m -U odoo
    HOME_DIR='/home/odoo'
}

write_conf_file () {
cat >etc/odoo.conf <<EOL
[options]
admin_passwd = admin

db_host = False
db_port = False
db_user = odoo
db_password = False

dbfilter = ^myproject_.*\$
addons_path = $HOME_DIR/odoo-venv/odoo/addons,$HOME_DIR/addons
data_dir = $HOME_DIR/data

server_wide_modules = web
without_demo = True
translate_modules = ['all']

list_db = False
debug_mode = False

workers = $(echo $[2*$(grep -c ^processor /proc/cpuinfo)+1])
max_cron_threads = 1
limit_memory_hard = 7247757312
limit_memory_soft = 6039797760
limit_time_cpu = 1200
limit_time_real = 2400

xmlrpc = True
xmlrpc_interface = 127.0.0.1
xmlrpc_port = 8069
longpolling_port  = 8072
proxy_mode = False


;log_handler="[':DEBUG']"]
log_handler=[':info']
log_level=info
logrotate = True
logfile = $HOME_DIR/log/odoo/odoo.log

EOL
    chown odoo:odoo etc/odoo.conf
    chmod 640 etc/odoo.conf
}

create_odoo_start () {
    mkdir bin
cat >bin/odoo_start <<EOL
#!/bin/bash
NAME="Odoo Eleven CE"
ENVBIN=$HOME_DIR/odoo-venv/bin
USER=odoo
GROUP=odoo
source \$ENVBIN/activate
exec \$ENVBIN/odoo --config=$HOME_DIR/etc/odoo.conf
EOL
    chmod +x bin/odoo_start
}

create_supervisord_entry () {
    touch /etc/supervisord.d/odoo_eleven.ini
cat >/etc/supervisord.d/odoo_eleven.ini <<EOL
[program:odooeleven]
command = /home/odoo/bin/odoo_start
user = odoo
stdout_logfile=/home/odoo/log/odoo/odoo_supervisor.log
stderr_logfile=/home/odoo/log/odoo/odoo_supervisor.log
autostart=true
autorestart=true
startsecs=10
stopwaitsecs=600
redirect_stderr = true
environment=LANG=en_US.UTF-8,LC_ALL=en_US.UTF-8
priority=200
stopsignal=INT
EOL
}

if [ -f /etc/debian_version ]; then
    echo "Installing dependencies for debian based distro"

    if [ "$developer" = true ]; then
        HOME_DIR='.'
    else
        create_odoo_user
        cd "$HOME_DIR"
    fi

    apt install build-essential gcc libglib2.0-dev -y
    apt install wget git bzr postgresql-9.6 python3 python3-dev libldap2-dev libjpeg-dev libfreetype6 libfreetype6-dev libpng-dev zlib1g-dev libkrb5-dev openssl libssl-dev libffi-dev libgmp3-dev -y
    apt install node-clean-css node-less supervisor -y
    systemctl start supervisord
    systemctl enable supervisord

    wget https://bootstrap.pypa.io/get-pip.py
    python3 get-pip.py

    apt install fontconfig libx11-6 libx11-dev libxext-6 libxext-dev libxrender1 libxrender-dev -y
    wget https://downloads.wkhtmltopdf.org/0.12/0.12.1/wkhtmltox-0.12.1_linux-trusty-amd64.deb
    dpkg -i wkhtmltox-0.12.1_linux-trusty-amd64.deb
    ln -s /usr/local/bin/wkhtmltopdf /usr/bin
    ln -s /usr/local/bin/wkhtmltoimage /usr/bin

    echo "Creating log directory [/var/log/odoo]"
    mkdir log
    chown odoo:odoo log
    mkdir log/odoo
    chown odoo:odoo log/odoo

    echo "Creating virtualenv for odoo"
    cd "$HOME_DIR"
    python3 -m venv odoo-venv
    chown -R odoo:odoo odoo-venv
    cd odoo-venv
    source bin/activate

    pip install --upgrade pip

    echo "Cloning odoo from github"
    git clone --depth 1 --branch 11.0 https://www.github.com/odoo/odoo

    cd odoo
    pip install -r requirements.txt
    python setup.py build
    python setup.py install

    cd "$HOME_DIR"
    mkdir addons
    chown -R odoo:odoo addons
    mkdir data
    chown -R odoo:odoo data
    mkdir etc
    chown -R odoo:odoo etc

    cp odoo-venv/odoo/debian/odoo.conf etc/odoo.conf
    write_conf_file

    if [ "$developer" = true ]; then

        su - postgres -c "createuser -s $(whoami)" 2> /dev/null || true

    else

        su - postgres -c "createuser -s odoo" 2> /dev/null || true

        create_odoo_start
        create_supervisord_entry
        supervisorctl reload

    fi

    exit
elif [ -f /etc/redhat-release ]; then
    echo "Installing dependencies for RedHat based distro"

    if [ "$developer" = true ]; then
        HOME_DIR='.'
    else
        create_odoo_user
        cd "$HOME_DIR"
    fi

    yum install epel-release -y
    yum install wget git bzr -y # postgresql-server postgresql-devel postgresql-contrib -y
    wget https://download.postgresql.org/pub/repos/yum/9.6/redhat/rhel-7-x86_64/pgdg-centos96-9.6-3.noarch.rpm
    yum install pgdg-centos96-9.6-3.noarch.rpm -y
    yum update
    yum install postgresql96-server postgresql96-contrib -y
    /usr/pgsql-9.6/bin/postgresql96-setup initdb
    systemctl start postgresql-9.6
    systemctl enable postgresql-9.6
    yum install gcc glibc-devel -y
    yum install openldap-devel libjpeg libjpeg-devel freetype-devel libpng-devel zlib zlib-devel krb5-devel openssl openssl-devel libffi libffi-devel gmp gmp-devel -y
    yum install python34 python34-devel -y
    yum install nodejs-clean-css nodejs-less supervisor -y
    systemctl start supervisord
    systemctl enable supervisord

    wget https://bootstrap.pypa.io/get-pip.py
    python3 get-pip.py

    yum install fontconfig fontconfig-devel libX11 libX11-devel libXext libXext-devel libXrender libXrender-devel -y
    wget https://downloads.wkhtmltopdf.org/0.12/0.12.1/wkhtmltox-0.12.1_linux-centos7-amd64.rpm
    rpm -i wkhtmltox-0.12.1_linux-centos7-amd64.rpm
    ln -s /usr/local/bin/wkhtmltopdf /usr/bin
    ln -s /usr/local/bin/wkhtmltoimage /usr/bin

    echo "Creating log directory [/var/log/odoo]"
    mkdir log
    chown odoo:odoo log
    mkdir log/odoo
    chown odoo:odoo log/odoo

    echo "Creating virtualenv for odoo"
    cd "$HOME_DIR"
    python3 -m venv odoo-venv
    chown -R odoo:odoo odoo-venv
    cd odoo-venv
    source bin/activate
    echo $(python -c 'import sys; print(sys.path)')

    pip install --upgrade pip

    echo "Cloning odoo from github"
    git clone --depth 1 --branch 11.0 https://www.github.com/odoo/odoo

    cd odoo
    pip install -r requirements.txt
    python setup.py build
    python setup.py install

    cd "$HOME_DIR"
    mkdir addons
    chown -R odoo:odoo addons
    mkdir data
    chown -R odoo:odoo data
    mkdir etc
    chown -R odoo:odoo etc

    cp odoo-venv/odoo/debian/odoo.conf etc/odoo.conf
    write_conf_file

    if [ "$developer" = true ]; then

        su - postgres -c "createuser -s $(whoami)" 2> /dev/null || true

    else

        su - postgres -c "createuser -s odoo" 2> /dev/null || true

        create_odoo_start
        create_supervisord_entry
        supervisorctl reload

    fi

    exit
else
    echo "Architecture not detected! Exiting"
    exit 1
fi

