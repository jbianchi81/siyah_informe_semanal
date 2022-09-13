# create environment and enter it
python3 -m venv .
source bin/activate

# install dependencies
python3 -m pip install -r requirements.txt

# edit project settings
nano settings.py 
# Search for DATABASES, set DB connection parameters (NOTE: database must be created before migration)
# Search for ENGINE and set according to your database engine
# set TIME_ZONE 

# migrate database (NOTE: database must be created before migration. Make sure the specified user has the right privileges)
python3 manage.py migrate
python3 manage.py makemigrations semanal
python3 manage.py migrate

# make initial data import
python3 etc/initial_import.py

# create superuser for admin interface
python3 manage.py createsuperuser