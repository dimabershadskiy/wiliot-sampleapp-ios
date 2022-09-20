Getting started
To run this sample project you need to edit "SampleAuthConstants.plist" with such content:
ext {
    owner_id = "\"owner_id_that_was_used_during_api_key_creation\""
    api_token = "\"your_generated_api_key\""
}
Api Key
In order to generate your API KEY you should go to platform.wiliot.com/account/security and press 'Add New'. In the Add Key dialog please choose Edge Management from dropdown menu 'Select Catalog' and press 'Generate'. Then you can use your API KEY to get Access Token.
Tokens
Access token and gateway token has limited life time. When it expires you should to refresh them.
