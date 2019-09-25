# Jamf-Pro-Object-LookUp
Script to query Jamf Pro and find what an Object is associated with

the script will prompt For Jamf Pro URL, username and password, after which you can select an 
Object type from the list of: Packages, Scripts, Printers, Computer Groups, or Mobile Device Groups

After which you choose your specific object from the next list and a report will be saved to the users desktop with a list of what policies a package, script or printer is assigned to.

If you select Computer Group it will display what policy, profile, patch policy, restricted software, mac app store and if it is a criteria of a nested smart group.

If you select Mobile Device Group it will display what profile, Mobile Device App and if it is a criteria for a Mobile Device Smart Group
