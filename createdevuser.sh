#!/bin/bash

# -----------------------------------------------------------------------------
# Script to set up dev accounts on a web development machine
#
# Creates:
# -- User SSH login
# -- FTP access to home directory (assumes this is available with login creation) 
# -- MySQL access to username_* databases (plus .my.cnf file in home directory)
# -- Self-signed SSL key/certificate in ~/.ssl[/certs] 
# -- Apache config file (enabled, with graceful reload)
#
# Assumes:
# -- Valid /root/.my.cnf file to enable mysql user creation
# -- Wildcard DNS entry for $SERVERDOMAIN variable (defined below these notes)
# -- chroot'd FTP access for user accounts by default 
# -- Apache2 web server correctly configured and running
#
# Issues
# -- No real security (passwords in command history, but are expected to be changed)
# -- No real error-checking, assumes success unless catastrophic failure
# -----------------------------------------------------------------------------



# ------ Variables ------

# Used for apache config file setup
SERVERDOMAIN="domain.com" 

# Used for self-signed certificates
SSLCOUNTRY="GB"
SSLSTATE="London"
SSLLOCATION="London"
SSLORGANISATION="Organisation"

# ------ End variables ------




# Check run as root
if [ $EUID -ne 0 -o $UID -ne 0 ]
then
        echo -e "Error - must be root.\nUsage:  createdevuser.sh username password\n" ;
        exit 1 ;
fi

# Check username and password arguments provided
if [ $# -ne 2 ]
then
        echo -e "Error - incorrect number of parameters\nUsage:  createdevuser.sh username password\n" ;
        exit 2 ;
fi


# Set up human-readable variables from command line arguments
NEWUSER=$1 ;
NEWPASS=$2 ;
NEWPASS_CRYPT=`openssl passwd -1 $NEWPASS` ;

# Check for existing user
egrep "^$NEWUSER" /etc/passwd >/dev/null
if [ $? -eq 0 ]; then
                echo -e "Error - user $NEWUSER already exists." ;
                exit 3 ;
fi

# Confirm creation
read -s -n 1 -p "Create new user \"$NEWUSER\" with password \"$NEWPASS\"? (y/n)" CONFIRM ; echo ;

if [ "$CONFIRM" != "y" ]
then
        echo -e "\nCancelled." ;
        exit 4 ;
else
        echo -e "\nProcessing:" ;
fi


# Create local user
echo -e -n "Creating local user..."
useradd -m --shell=/bin/bash -p "$NEWPASS_CRYPT" $NEWUSER ;
echo -e -n "Done.\n"

# Create samba user
# Not needed for external host
#echo -e -n "Creating SAMBA user..."
### Should use inline herestring: <<< "
#(echo -e -n "$NEWPASS\n$NEWPASS\n") | sudo smbpasswd -a -s $NEWUSER > /dev/null;
#echo -e -n "$NEWUSER = \"$NEWUSER\"\n" >> /etc/samba/smbusers ;
#echo -e -n "Done.\n"

# Create FTP User
# Actually implicit with succesful user creation but nice to see in the output
echo -e -n "Creating FTP user..."
echo -e -n "Done.\n"


# Create mysql user and .my.cnf file
echo -e -n "Creating mysql user..."
mysql --defaults-extra-file="/root/.my.cnf" -e "GRANT ALL ON \`${NEWUSER}_%\`.* to '$NEWUSER'@'localhost' IDENTIFIED BY '$NEWPASS';" ;
echo -ne "[client]\nuser=$NEWUSER\npassword=$NEWPASS\n" > /home/$NEWUSER/.my.cnf
chown $NEWUSER:$NEWUSER /home/$NEWUSER/.my.cnf
echo -e -n "Done.\n"


# Create self-signed key/certificate for HTTPS
echo -e -n "Creating self-signed SSL certficates..."
mkdir -p /home/$NEWUSER/.ssl/certs
openssl req -nodes -newkey rsa:2048 -x509 -days 1825 \
-subj "/C=$SSLCOUNTRY/ST=$SSLSTATE/L=$SSLLOCATION/O=$SSLORGANISATION/CN=$NEWUSER.$SERVERDOMAIN" \
-keyout /home/$NEWUSER/.ssl/$NEWUSER.$SERVERDOMAIN.key \
-out /home/$NEWUSER/.ssl/certs/$NEWUSER.$SERVERDOMAIN.crt \
> /dev/null 2>&1
chown -R $NEWUSER:$NEWUSER /home/$NEWUSER/.ssl
echo -e -n "Done.\n"


# Create apache site .conf file
# Done inline to keep script self-contained, but maybe not best option for flexibility
echo -e -n "Creating Apache site config file..."
cat > /etc/apache2/sites-available/$NEWUSER.$SERVERDOMAIN.conf <<EOF

<VirtualHost *:80>
  ServerName $NEWUSER.$SERVERDOMAIN
  ServerAdmin $NEWUSER@$SERVERDOMAIN
  DocumentRoot /home/$NEWUSER/public_html
  LogLevel warn
  ErrorLog \${APACHE_LOG_DIR}/error.$NEWUSER.$SERVERDOMAIN.log
  CustomLog \${APACHE_LOG_DIR}/access.$NEWUSER.$SERVERDOMAIN.log combined

  <Directory />
    Options FollowSymLinks
    AllowOverride None
  </Directory>

  <Directory /home/$NEWUSER/public_html/>
    Options All
    AllowOverride All
    Require all granted
  </Directory>

</VirtualHost>

<VirtualHost *:443>
  ServerName $NEWUSER.$SERVERDOMAIN
  ServerAdmin $NEWUSER@$SERVERDOMAIN
  DocumentRoot /home/$NEWUSER/public_html
  SSLEngine on
  SSLCertificateFile /home/$NEWUSER/.ssl/certs/$NEWUSER.$SERVERDOMAIN.crt
  SSLCertificateKeyFile /home/$NEWUSER/.ssl/$NEWUSER.$SERVERDOMAIN.key
</VirtualHost>
EOF

echo -e -n "Done.\n"

echo -e -n "Enabling Apache site config file..."
a2ensite $NEWUSER.$SERVERDOMAIN > /dev/null 2>&1
echo -e -n "Done.\n"

echo -e -n "Loading Apache site config file..."
mkdir -p /home/$NEWUSER/public_html # Make sure folder is there so `apache2ctl configtest` is happy
apache2ctl configtest > /dev/null 2>&1 && apache2ctl graceful > /dev/null 2>&1
echo -e -n "Done.\n"


# Complete
echo -e "\nUser creation complete." ;
echo "--> $NEWUSER.$SERVERDOMAIN is served from /home/$NEWUSER/public_html (which can be a symlink)" ;
exit 0 ;

