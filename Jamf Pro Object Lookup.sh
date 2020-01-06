#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
#
# Copyright (c) 2020, JAMF Software, LLC.  All rights reserved.
#
#       Redistribution and use in source and binary forms, with or without
#       modification, are permitted provided that the following conditions are met:
#               * Redistributions of source code must retain the above copyright
#                 notice, this list of conditions and the following disclaimer.
#               * Redistributions in binary form must reproduce the above copyright
#                 notice, this list of conditions and the following disclaimer in the
#                 documentation and/or other materials provided with the distribution.
#               * Neither the name of the JAMF Software, LLC nor the
#                 names of its contributors may be used to endorse or promote products
#                 derived from this software without specific prior written permission.
#
#       THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#       EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#       WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#       DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#       DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#       (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#       LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#       ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#       (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#       SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# This script is designed to be run that will query the Jamf Pro server and a list of the following
# 	- objects in a macOS Policy such as Packages, Scripts, and Printers
# 	- packages within a macOS Patch Management Policy
# 	- Items a macOS Group is assigned to or excluded from such as Policies, Patch Polcies, Profiles, Restricted Software and MacOS Apps as well as nested smart groups
# 	- Items a Mobile Device Group is assigned to or excluded from such as Profiles and Mobile Device Apps as well as nested smart groups
#
#
#	Once completed there will be a text file on the users desktop in the format of "OBJECT_NAME.day.month.year.txt"
#	for example Test_Group.25.09.2019.txt
#
#
# Written by: Daniel MacLaughlin | Implementation Engineer | Jamf
#
# Created On: September 19th 2019
# Updated On: January 6th 2020
# 	- Added reporting on packages in patch titles
#  	- Added diaglog prompts that inform when either a report is created or not 
#
# version 1.1
#
# 
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

#Lets get the current User so we can store the report on their Desktop
CURRENT_USER=$(/bin/ls -l /dev/console | awk '/ / { print $3 }')

# Since we like Data we can also do a timestamp this can be modified as dd.mm.yyyy or dd-mm-yyyy
TIME=$(/bin/date +"%d.%m.%Y")


#######Ask for JSS Address using Apple Script
SERVERURL=$(/usr/bin/osascript <<EOT 
tell application "System Events"
	activate
	set input to display dialog "Enter JSS Address: NO ENDING SLASH" default answer "https://server.jamfcloud.com" buttons {"Continue"} default button 1
	return text returned of input as string
end tell
EOT
)


#####Ask for JSS API Username using Apple Script
APIUSER=$(/usr/bin/osascript <<EOT
tell application "System Events"
	set input to display dialog "Enter JSS API Username:" default answer "Username" buttons {"Continue"} default button 1
	return text returned of input as string
end tell
EOT
)


######Ask for JSS API Password using Apple Script
APIPASSWORD=$(/usr/bin/osascript <<EOT
tell application "System Events"
	set input to display dialog "Enter JSS API password" default answer "Password" with hidden answer buttons {"Continue"} default button 1
	return text returned of input as string
end tell
EOT
)


#Prompt User for what type of item they want to get more information for ie packages, scripts,
OBJECT_TYPE=$(/usr/bin/osascript <<EOT
return choose from list {"Packages", "Scripts", "Printers", "Computer Groups", "Mobile Device Groups"}
EOT
)


#This is to replace the space with underscore for XML parsing in stylsheet
OBJECT_TYPE_ALTERED=$(/bin/echo $OBJECT_TYPE | tr '[:upper:]' '[:lower:]'| sed 's/ /_/g'  | sed 's/.\{1\}$//')


#This is to remove the upper case and spaces from the choice list for api calls
OBJECT_TYPE_MODIFIED=$(/bin/echo $OBJECT_TYPE | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')



#######################################
# Create an XSLT file for the Report Display List
#######################################
/bin/cat << EOF > /tmp/stylesheet.xslt
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/">
EOF
/bin/echo "<xsl:for-each select="\"//$OBJECT_TYPE_ALTERED\"">" >> /tmp/stylesheet.xslt
/bin/cat << EOL >> /tmp/stylesheet.xslt
		<xsl:value-of select="name"/>
		<xsl:text>&#xa;</xsl:text> 
	</xsl:for-each> 
</xsl:template> 
</xsl:stylesheet>
EOL

# using the export the list using stylesheet to be a text file to be used for the next display prompt
OBJECT_LIST=$(/usr/bin/curl -u "$APIUSER:$APIPASSWORD" -H "Accept: application/xml" "$SERVERURL/JSSResource/$OBJECT_TYPE_MODIFIED" | xsltproc /tmp/stylesheet.xslt - > /tmp/object_list.txt)

#display to the user the list of specific objects referencing the text file from the list
OBJECT_SPECIFIC=$(/usr/bin/osascript <<EOT
	tell application "System Events"
		with timeout of 43200 seconds
			activate
			set ObjectList to {}
			set ObjectFile to paragraphs of (read POSIX file "/tmp/object_list.txt")
			repeat with i in ObjectFile
				if length of i is greater than 0 then
					copy i to the end of ObjectList
				end if
			end repeat
			choose from list ObjectList with title "Which Object" with prompt "Please select the Object you'd like to find out about:"
		end timeout
	end tell
EOT
)

#Report Path as Variable
REPORT_RAW="/Users/$CURRENT_USER/Desktop/${OBJECT_SPECIFIC}.${TIME}.txt"
#Removing any spaces from the path for export
REPORT_PATH=$(echo $REPORT_RAW | sed -e 's/ /_/g')

#xpath variable based on the object type to update the xpath path along with type to seperate between object, computer group and mobile group
if [[ $OBJECT_TYPE == "Packages" ]];then
	XPATH_VARIABLE="//package_configuration/packages/package/name"
	TYPE="Computer"
	elif
	[[ $OBJECT_TYPE == "Scripts" ]];then
		XPATH_VARIABLE="//scripts/script/name"
		TYPE="Computer"
	elif
	[[ $OBJECT_TYPE == "Printers" ]];then
		XPATH_VARIABLE="//printers/printer/name"
		TYPE="Computer"
	elif
	[[ $OBJECT_TYPE == "Computer Groups" ]];then
		XPATH_VARIABLE="//scope/computer_groups/computer_group/name"
		XPATH_EXCLUSION_VARIABLE="//scope/exclusions/computer_groups/computer_group/name"
		TYPE="Computer Group"
	elif
	[[ $OBJECT_TYPE == "Mobile Device Groups" ]];then
		XPATH_VARIABLE="//scope/mobile_device_groups/mobile_device_group/name"
		XPATH_EXCLUSION_VARIABLE="//scope/exclusions/mobile_device_groups/mobile_device_group/name"
		TYPE="Mobile Device Group"
	fi


#get information for Computer Groups, objects that are checked are policies, profiles, macAppStore and restricted software
if [[ $TYPE == "Computer Group" ]];then
	
	/bin/echo "##################### Getting Policy Groups ########################"
	
	#Get an array of policy id's
	MAC_POLICY_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/policies" | xpath '//policy' 2>&1 | awk -F'<id>|</id>' '{print $2}')
	#cycle through each policy id to get name and scopes
	for id in $MAC_POLICY_ID;do
		#Get the Polcy Name for the Report
		POLICY_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/policies/id/$id" | xpath '/policy/general/name/text()')
		#Get the Scope of the policy as an array
		MAC_SCOPE_POLICY=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/policies/id/$id" | xpath $XPATH_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
		#Get the Exclusion scope as an array
		MAC_EXCLUSION_POLICY=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/policies/id/$id" | xpath $XPATH_EXCLUSION_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
			#Check to see if the group is in the scope and if so write to text file
			while read -r fname; do
					if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
						/bin/echo "The policy $POLICY_NAME has the group $OBJECT_SPECIFIC" >> $REPORT_PATH
					fi
			done <<< "$MAC_SCOPE_POLICY"
			#check to see if the group is excluded from the policy and if so export to text file
			while read -r fname; do
					if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
						/bin/echo "The policy $POLICY_NAME has the group $OBJECT_SPECIFIC excluded" >> $REPORT_PATH
					fi
			done <<< "$MAC_EXCLUSION_POLICY"
		done
		
		/bin/echo "##################### Getting macOS Profile Groups ########################"
		#get macOS profile id's an array
		MAC_PROFILE_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/osxconfigurationprofiles" | xpath '//os_x_configuration_profile' 2>&1 | awk -F'<id>|</id>' '{print $2}')
		
		#Cycle through profile ID's to get name and scope
		for id in $MAC_PROFILE_ID;do
			#get Profile Name
			PROFILE_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/osxconfigurationprofiles/id/$id" | xpath '/os_x_configuration_profile/general/name/text()')
			#Get the scope of groups as an array 
			MAC_SCOPE_PROFILE=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/osxconfigurationprofiles/id/$id" | xpath $XPATH_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
			#Get the Exclusion list of groups for the profile
			MAC_EXCLUSION_PROFILE=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/osxconfigurationprofiles/id/$id" | xpath $XPATH_EXCLUSION_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
			
				#Cycle through the Scoped groups to see if it matches the object if so export to text file
				while read -r fname; do
						if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
							/bin/echo "The profile $PROFILE_NAME has the group $OBJECT_SPECIFIC" >> $REPORT_PATH
						fi
				done <<< "$MAC_SCOPE_PROFILE"
				#Cycle through the excluded groups and if it matches the object then export to the text file
				while read -r fname; do
						if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
							/bin/echo "The profile $PROFILE_NAME has the group $OBJECT_SPECIFIC excluded" >> $REPORT_PATH
						fi
				done <<< "$MAC_EXCLUSION_PROFILE"
			done

			/bin/echo "##################### Getting Patch Policy Groups ########################"
			#Get macOS restricted software id's as an array
			MAC_PATCH_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/patchpolicies" | xpath '//patch_policy' 2>&1 | awk -F'<id>|</id>' '{print $2}')

			#Cycle through the id's to get Name and Scope
			for id in $MAC_PATCH_ID;do
				#Get restricted software app name
				MAC_PATCH_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/patchpolicies/id/$id" | xpath '/patch_policy/general/name/text()')

				#Get the scope of the restricted software app as an array
				MAC_SCOPE_PATCH=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/patchpolicies/id/$id/subset/Scope" | xpath $XPATH_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
				
				#Get the exclusion scope of the restricted app as an array 
				MAC_EXCLUDED_PATCH=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/patchpolicies/id/$id/subset/Scope" | xpath $XPATH_EXCLUSION_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
				
					#cycle through the list of groups and if it matches export to text file
					while read -r fname; do
							if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
								/bin/echo "The Patch Policy $MAC_PATCH_NAME has the group $OBJECT_SPECIFIC" >> $REPORT_PATH
							fi
					done <<< "$MAC_SCOPE_PATCH"
					
					#cycle through the excluded groups and if it matches export it to text file
					while read -r fname; do
							if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
								/bin/echo "The Patch Policy $MAC_PATCH_NAME has the group $OBJECT_SPECIFIC excluded" >> $REPORT_PATH
							fi
					done <<< "$MAC_EXCLUDED_PATCH"
				done
	
	/bin/echo "##################### Getting macOS Restriction Groups ########################"
	#Get macOS restricted software id's as an array
	MAC_RESTRICTED_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/restrictedsoftware" | xpath '//restricted_software_title' 2>&1 | awk -F'<id>|</id>' '{print $2}')
	#Cycle through the id's to get Name and Scope
	for id in $MAC_RESTRICTED_ID;do
		#Get restricted software app name
		RESTRICTED_APP_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/restrictedsoftware/id/$id" | xpath '/restricted_software/general/name/text()')
		#Get the scope of the restricted software app as an array
		MAC_SCOPE_RESTRICTED_APP=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/restrictedsoftware/id/$id" | xpath $XPATH_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
		#Get the exclusion scope of the restricted app as an array 
		MAC_EXCLUDED_RESTRICTED_APP=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/restrictedsoftware/id/$id" | xpath $XPATH_EXCLUSION_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
		
			#cycle through the list of groups and if it matches export to text file
			while read -r fname; do
					if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
						/bin/echo "The restricted app $RESTRICTED_APP_NAME has the group $OBJECT_SPECIFIC" >> $REPORT_PATH
					fi
			done <<< "$MAC_SCOPE_RESTRICTED_APP"
			
			#cycle through the excluded groups and if it matches export it to text file
			while read -r fname; do
					if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
						/bin/echo "The restricted app $RESTRICTED_APP_NAME has the group $OBJECT_SPECIFIC excluded" >> $REPORT_PATH
					fi
			done <<< "$MAC_EXCLUDED_RESTRICTED_APP"
		done


		/bin/echo "##################### Getting macOS App Store App Groups ########################"
		#Get macOS App Store id's as an array
		MAC_APPSTORE_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/macapplications" | xpath '//mac_application' 2>&1 | awk -F'<id>|</id>' '{print $2}')
		#Cycle through the id's getting the Name, and Scope
		for id in $MAC_APPSTORE_ID;do
			#Get the macOS App Name
			MAC_APPSTORE_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/macapplications/id/$id" | xpath '/mac_application/general/name/text()')
			#Get the macOS App Store Scope
			MAC_SCOPE_APPSTORE=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/macapplications/id/$id" | xpath $XPATH_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
			#Get the macOS App Store Excluded Scope
			MAC_EXCLUSION_APPSTORE=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/macapplications/id/$id" | xpath $XPATH_EXCLUSION_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
			
				#Cycle through scope list to see if it matches and if found will export to text file
				while read -r fname; do
						if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
							/bin/echo "The macApp $MAC_APPSTORE_NAME has the group $OBJECT_SPECIFIC" >> $REPORT_PATH
						fi
				done <<< "$MAC_SCOPE_APPSTORE"
				
				#Cycle through exclusion scope list to see if it matches and if so export to text file
				while read -r fname; do
						if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
							/bin/echo "The macApp $MAC_APPSTORE_NAME has the group $OBJECT_SPECIFIC excluded" >> $REPORT_PATH
						fi
				done <<< "$MAC_EXCLUSION_APPSTORE"
			done

			/bin/echo "##################### Getting Smart Groups ########################"
			#Get an array of group id's
			MAC_GROUP_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/computergroups" | xpath '//computer_group' 2>&1 | awk -F'<id>|</id>' '{print $2}')
			#cycle through each group id to get name and if member of a smart group
			for id in $MAC_GROUP_ID;do
				#Get the Group Name for the Report
				GROUP_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/computergroups/id/$id" | xpath '/computer_group/name/text()')
				
				#get subset of groups that have "Computer Group" as criteria
				GROUP_CRITERIA_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/computergroups/id/$id" | xpath /computer_group/criteria/criterion/name 2>&1 | awk -F'<name>|</name>' '{print $2}')
				#Cycle though the array of smart groups with "Computer Group as criteria
				while read -r fname; do
						if [[ "$fname" == "Computer Group" ]];then
						#Get the value of the Computer Group Criteria to see if it matches
						GROUP_CRITERIA_VALUE=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/computergroups/id/$id" | xpath /computer_group/criteria/criterion/value 2>&1 | awk -F'<value>|</value>' '{print $2}')
							while read -r fname; do
									if [[ "$fname" == "$OBJECT_SPECIFIC" ]];then
							
									/bin/echo "The Group $GROUP_NAME has the criteria $OBJECT_SPECIFIC"  >> $REPORT_PATH
							fi
							done <<< "$GROUP_CRITERIA_VALUE"
						fi
					done <<< "$GROUP_CRITERIA_NAME"
				done
fi


#get information for Mobile Device Groups, objects that are checked are, profiles, and AppStore apps
if [[ $TYPE == "Mobile Device Group" ]];then

	/bin/echo "##################### Getting Mobile Profile Groups ########################"
	#Get iOS profile id's as an array
	iOS_PROFILE_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledeviceconfigurationprofiles" | xpath '//configuration_profile' 2>&1 | awk -F'<id>|</id>' '{print $2}')
	#Cycle through the ids to get profile name and scope
	for id in $iOS_PROFILE_ID;do
		#get the Profile name
		iOS_PROFILE_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledeviceconfigurationprofiles/id/$id" | xpath '/configuration_profile/general/name/text()')
		#Get the iOS Scope as an array
		iOS_SCOPE_PROFILE=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledeviceconfigurationprofiles/id/$id" | xpath $XPATH_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
		#Get the iOS Profile exclusions as an array
		iOS_EXCLUSION_PROFILE=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledeviceconfigurationprofiles/id/$id" | xpath $XPATH_EXCLUSION_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
			
			#Cycle through array and if the group matches export to text file
			while read -r fname; do
					if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
						/bin/echo "The profile $iOS_PROFILE_NAME has the group $OBJECT_SPECIFIC" >> "${REPORT_PATH}"
					fi
			done <<< "$iOS_SCOPE_PROFILE"
			
			
			while read -r fname; do
					if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
						/bin/echo "The profile $iOS_PROFILE_NAME has the group $OBJECT_SPECIFIC excluded" >> "${REPORT_PATH}"
					fi
			done <<< "$iOS_EXCLUSION_PROFILE"
		done
	
	
	/bin/echo "##################### Getting Mobile App Groups ########################"
	#Get iOS AppStore ID's
	iOS_APP_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledeviceapplications" | xpath '//mobile_device_application' 2>&1 | awk -F'<id>|</id>' '{print $2}')
	#Cycle through app store id's to get Name and Scope
	for id in $iOS_APP_ID;do
		#Get iOS App Name
		iOS_APP_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledeviceapplications/id/$id" | xpath '/mobile_device_application/general/name/text()')
		#Get iOS Scope as an array
		iOS_SCOPE_APP=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledeviceapplications/id/$id" | xpath $XPATH_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
		#iOS Exclusion scope as array
		iOS_EXCLUSION_APP=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledeviceapplications/id/$id" | xpath $XPATH_EXCLUSION_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
		
			#Cycle through the array and if it matches export to text file
			while read -r fname; do
					if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
						/bin/echo "The iOS App $iOS_APP_NAME has the group $OBJECT_SPECIFIC" >> "${REPORT_PATH}"
					fi
			done <<< "$iOS_SCOPE_APP"
			
			#Cycle through the array and if it matches export to text file
			while read -r fname; do
					if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
						/bin/echo "The iOS App $iOS_APP_NAME has the group $OBJECT_SPECIFIC excluded" >> "${REPORT_PATH}"
					fi
			done <<< "$iOS_EXCLUSION_APP"
		done
		
		/bin/echo "##################### Getting Mobile Device Smart Groups ########################"
		#Get an array of group id's
		iOS_GROUP_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledevicegroups" | xpath '//mobile_device_group' 2>&1 | awk -F'<id>|</id>' '{print $2}')
		#cycle through each group id to get name and if member of a smart group
		for id in $iOS_GROUP_ID;do
			#Get the Group Name for the Report
			GROUP_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledevicegroups/id/$id" | xpath '/mobile_device_group/name/text()')
			
			#get subset of groups that have "Computer Group" as criteria
			GROUP_CRITERIA_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledevicegroups/id/$id" | xpath /mobile_device_group/criteria/criterion/name 2>&1 | awk -F'<name>|</name>' '{print $2}')

			#Cycle though the array of smart groups with "Mobile Device Group as criteria
			while read -r fname; do
					if [[ "$fname" == "Mobile Device Group" ]];then
					#Get the value of the Mobile Device Group Criteria to see if it matches
					GROUP_CRITERIA_VALUE=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/mobiledevicegroups/id/$id" | xpath /mobile_device_group/criteria/criterion/value 2>&1 | awk -F'<value>|</value>' '{print $2}')

						while read -r fname; do
								if [[ "$fname" == "$OBJECT_SPECIFIC" ]];then
								/bin/echo "The Group $GROUP_NAME has the criteria $OBJECT_SPECIFIC"  >> "${REPORT_PATH}"
						fi
						done <<< "$GROUP_CRITERIA_VALUE"
					fi
				done <<< "$GROUP_CRITERIA_NAME"
			done
fi


#Get information specific to polices in terms of the contents such as scripts, packages and printers
if [[ $TYPE == "Computer" ]];then

#find all pack inside policies
#Download from API and provide array of device id's
/bin/echo "##################### Getting Policies ########################"

MAC_POLICY_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/policies" | xpath '//policy' 2>&1 | awk -F'<id>|</id>' '{print $2}')

#cycle through id's and export data
for id in $MAC_POLICY_ID;do

POLICY_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/policies/id/$id" | xpath '/policy/general/name/text()')

MAC_POLICY_OBJECTS=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/policies/id/$id" | xpath $XPATH_VARIABLE 2>&1 | awk -F'<name>|</name>' '{print $2}')
	
	#Cycle through the Object list and export to Text File
	while read -r fname; do
			if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
				/bin/echo "The policy $POLICY_NAME has the $OBJECT_SPECIFIC" >> "${REPORT_PATH}"
			fi
	done <<< "$MAC_POLICY_OBJECTS"

done

#Download from API and provide array of device id's
/bin/echo "##################### Getting Patch Policies Titles ########################"

MAC_PATCH_TITLE_ID=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/patchsoftwaretitles" | xpath '//patch_software_title' 2>&1 | awk -F'<id>|</id>' '{print $2}')

#cycle through id's and export data
for id in $MAC_PATCH_TITLE_ID;do
	
MAC_PATCH_TITLE_NAME=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/patchsoftwaretitles/id/$id" | xpath '/patch_software_title/name/text()')

MAC_PATCH_TITLE_OBJECTS=$(/usr/bin/curl -H "Accept: application/xml" -sku "$APIUSER":"$APIPASSWORD" "$SERVERURL/JSSResource/patchsoftwaretitles/id/$id" | xpath //versions/version/package 2>&1 | awk -F'<name>|</name>' '{print $2}')
	
	#Cycle through the Object list and export to Text File
	while read -r fname; do
			if [[ "$OBJECT_SPECIFIC" == "$fname" ]];then
				/bin/echo "The Patch Management title $MAC_PATCH_TITLE_NAME has the $OBJECT_SPECIFIC" >> "${REPORT_PATH}"
			fi
	done <<< "$MAC_PATCH_TITLE_OBJECTS"
done

fi

#Check if a Report was created, if not then the item selected is not a memeber of anything, otherwise display dialog of the report path
if [ -f ${REPORT_PATH} ];then
	REPORT_SUCCESS=$(/usr/bin/osascript <<EOT
	tell application "System Events"
	display dialog "Report Created at \"$REPORT_PATH\"" with icon note 
	end tell
EOT
)
	else
	REPORT_FAILED=$(/usr/bin/osascript <<EOT
	tell application "System Events"
	display dialog "\"$OBJECT_SPECIFIC\" Not associated with anything, report not created" with icon caution 
	end tell
EOT
)
fi