#!/usr/bin/env python2.5

"""
Please see the README for detailed instructions for running this agent.

"""

''' Account Id is available from the Settings tab in Ylastic '''
YLASTIC_ACCOUNT_ID=""

''' AWS account numbers without the hyphens. You can add upto 15 accounts.'''
AWS_ACCOUNT_NUM=["1111","2222"]

''' Usernames and passwords for the AWS site for each of the account numbers
specified above.'''
AWS_USERNAME=["me@me.com","one@me.com"]
AWS_PASSWORD=["pw1","pw2"]

''' Temp directory where you want to download the usage data '''
DOWNLOAD_DIR = "/tmp"


''' YOU ONLY NEED TO CUSTOMIZE THE ABOVE PARAMS '''

import os
import sys
import time
import logging
from datetime import date
from urllib import urlretrieve
from zipfile import ZipFile, ZIP_DEFLATED
import re

ylogger = logging.getLogger("ylastic_aws_costs_agent")
ylogger.setLevel(logging.DEBUG)
lf = logging.FileHandler("%s/ylastic_aws_costs_agent.log" %(DOWNLOAD_DIR))
f = logging.Formatter("%(levelname)s %(asctime)s %(funcName)s %(lineno)d %(message)s")
lf.setFormatter(f)
lf.setLevel(logging.DEBUG)
ylogger.addHandler(lf)

try:
    import mechanize
except ImportError, e:
    yl = logging.getLogger("ylastic_aws_costs_agent")
    yl.debug("\nYou do not have the prerequisite 'mechanize' package installed in your Python environment.\nIt is available from http://wwwsearch.sourceforge.net/mechanize/. \nIf you have 'setuptools' available, you can install it like this : easy_install mechanize\n")
    sys.exit("\nYou do not have the prerequisite 'mechanize' package installed in your Python environment.\nIt is available from http://wwwsearch.sourceforge.net/mechanize/. \nIf you have 'setuptools' available, you can install it like this : easy_install mechanize\n")

try:
    from BeautifulSoup import BeautifulSoup
except ImportError, e:
    yl = logging.getLogger("ylastic_aws_costs_agent")
    yl.debug("\nYou do not have the prerequisite 'BeautifulSoup' package installed in your Python environment.\nIt is available from http://www.crummy.com/software/BeautifulSoup/#Download. \nIf you have 'setuptools' available, you can install it like this : easy_install BeautifulSoup\n")
    sys.exit("\nYou do not have the prerequisite 'BeautifulSoup' package installed in your Python environment.\nIt is available from http://www.crummy.com/software/BeautifulSoup/#Download. \nIf you have 'setuptools' available, you can install it like this : easy_install BeautifulSoup\n")

services_list_path = os.path.join(DOWNLOAD_DIR, 'cost_services.list')
yl = logging.getLogger("ylastic_aws_costs_agent")
yl.debug("Retrieving list of services for which need to download usage data ...")
urlretrieve('http://ylastic.com/cost_services.list', services_list_path)
services_list_file = open ( services_list_path, 'r' )
services_list = services_list_file.read().strip().split(',')
services_list_file.close()
SERVICES = tuple(services_list)
yl.debug("Retrieved the list of services for which need to download usage data")

FORM_URL = "https://aws-portal.amazon.com/gp/aws/developer/account/index.html?ie=UTF8&action=usage-report"


def get_raw_usage_data():
    yl = logging.getLogger("ylastic_aws_costs_agent")
    yl.debug("--------------------------------------------------")
    yl.debug("Starting ...")

    index = 0
    for aws_account in AWS_ACCOUNT_NUM:
        yl.debug("Logging in to download raw usage reports for account %s ..." % aws_account)
        for service in SERVICES:
            num_tries = 3
            while num_tries > 0:
                br = mechanize.Browser(factory=mechanize.RobustFactory())
                br.set_handle_robots(False)
    
                br.addheaders = [
                    ('User-Agent', 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.1) Gecko/20090701 Ubuntu/9.04 (jaunty) Firefox/3.5'),
                    ('Accept', 'text/html, application/xml, */*'),
                ]
    
                # login
                try:
                    br.open(FORM_URL)
                    resp = br.response()
                    san_data = BeautifulSoup(resp.get_data())
                    p = re.compile(r'\s+')
                    san_data2 = p.sub(' ', str(san_data))
                    resp.set_data(str(san_data2))
                    br.set_response(resp)
                    br.select_form(name="signIn")
                    br["email"] = AWS_USERNAME[index]
                    br["password"] = AWS_PASSWORD[index]
                    resp = br.submit()  # submit current form
                except Exception, e:
                    yl.exception("Error logging in to AWS to download usage report. Check your username and pw.")
                    print "Error logging in to AWS to download usage report. Check your username and pw."
                    sys.exit(1)
    
                # service selector
                d = date.today()
                next_month = d.month + 1
                year = d.year
                if d.month == 12:
                    next_month = 1
                    year = year + 1
                dates = ['2010-01-01',"%s-%s-01" %(year, next_month)]
                date_range = [date(*time.strptime(dates[i], '%Y-%m-%d')[0:3]) for i in range(2)]
                date_from = date_range[0]
                date_to = date_range[1]
    
                yl.debug("Selecting reports for %s..." % service)
                try:
                    br.select_form(name="usageReportForm")
                except mechanize._mechanize.FormNotFoundError:
                    yl.exception("Error logging in to AWS to download usage report. Check your username and pw.")
                    print "Error logging in to AWS to download usage report. Check your username and pw."
                    sys.exit(1)
                
                try:
                    br["productCode"] = [service]
                except mechanize._form.ItemNotFoundError:
                    yl.debug("User not signed up for %s. Skipping ..." % service)
                    num_tries = 0
                    break
                resp = br.submit()
    
                # report selector
                yl.debug("Building the usage report...")
                br.select_form(name="usageReportForm")
                br["timePeriod"] = ["aws-portal-custom-date-range"]
                br["startYear"] = [str(date_from.year)]
                br["startMonth"] = [str(date_from.month)]
                br["startDay"] = [str(date_from.day)]
                br["endYear"] = [str(date_to.year)]
                br["endMonth"] = [str(date_to.month)]
                br["endDay"] = [str(date_to.day)]
                br["periodType"] = ["days"]
                format = 'csv'
                resp = br.submit("download-usage-report-%s" % format)
                filename = "%s_%s_%s.csv" % (YLASTIC_ACCOUNT_ID,aws_account,service)
                filepath = os.path.join(DOWNLOAD_DIR, filename)
                user_data_file = open ( filepath, 'w' )
                user_data_file.write(resp.read())
                user_data_file.close()
                file_size = os.stat(filepath).st_size
                if file_size < 70:
                    num_tries = num_tries - 1
                    time.sleep(15)
                else:
                    num_tries = 0
                    continue
                    
        filename = "%s_%s_aws_usage.zip" % (YLASTIC_ACCOUNT_ID,aws_account)
        filepath = os.path.join(DOWNLOAD_DIR, filename)
        yl.debug("Bundling all usage reports into zip file [%s] ..." %(filepath))
        os.chdir(DOWNLOAD_DIR)
        z = ZipFile(filepath, "w", ZIP_DEFLATED)
        for root, dirs, files in os.walk(DOWNLOAD_DIR):
            for name in files:
                if name.startswith(YLASTIC_ACCOUNT_ID) and name.endswith('.csv'):
                    z.write(name)
        z.close()

        filename = "%s_%s_aws_usage.zip" % (YLASTIC_ACCOUNT_ID,aws_account)
        filepath = os.path.join(DOWNLOAD_DIR, filename)
        yl.debug("Uploading zip file [%s] to Ylastic ..." %(filepath))
        try:
            br.open("http://ylastic.com/usage_upload.html")
            br.select_form(name="upload")
            br.form.add_file(open(filepath, "rb"), 'application/zip', filename)
            br.submit()
        except Exception, e:
            yl.exception("Failed to upload usage data to Ylastic")
            print "Failed to upload usage data to Ylastic"
            sys.exit(1)

        yl.debug("Done for account %s" % aws_account)
        index = index + 1

    yl.debug("Done")
    yl.debug("--------------------------------------------------")

if __name__ == "__main__":
    get_raw_usage_data()
