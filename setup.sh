# install postgresql 12
sudo apt install postgresql-12 postgresql-12-postgis
# start postgresql server
sudo service postgresql@12-main start 
# create super user
sudo su postgres
createuser my_user -d -s
exit
# create db meteorology
createdb meteorology
# create schema
psql meteorology -f sql/meteorology_functions.sql
psql meteorology -f sql/schema_basic.sql
# populate auxiliary tables
psql meteorology -f sql/dependencies_minimal_dump.sql
# install python 3.10
sudo apt install python3.10
# python3.10 -m django-admin startproject siyah_informe_semanal
# clone repo 
git clone https://github.com/jbianchi81/siyah_informe_semanal.git
cd siyah_informe_semanal
# create virtual env
python3.10 -m venv .
# start virtual env
source bin/activate
# install dependencies
python3.10 -m pip install -r dependencies.txt
# migrate models
python3.10 manage.py makemigrations semanal
python3.10 manage.py migrate
# load initial data
python3.10 manage.py loaddata fixtures/dump.yaml
# start app
python3.10 manage.py runserver
