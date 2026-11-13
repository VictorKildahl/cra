// Chrome's preferences as Cra's app sets and reads them (the CEF bridge's request-context preferences): the
// settings Cra applies to every profile as it loads, secure DNS in Local State, single prefs as JSON, and the
// changes the app listens for.
#ifndef CRA_PROFILE_PREFS_H_
#define CRA_PROFILE_PREFS_H_

#import <Foundation/Foundation.h>

class Profile;

namespace cra {

// Once Chrome is up: applies Cra's settings to the profiles loaded so far and to each one after.
void StartProfilePrefs();

void SetHttpsOnly(bool enabled);
void SetFingerprintingProtection(bool enabled);
// 0 Automatic (the Mac's), 1 Light, 2 Dark.
void SetWebsiteAppearance(NSInteger mode);
NSInteger WebsiteAppearance();

NSString* SecureDNSPreference(const char* name);
bool SetSecureDNS(NSString* mode, NSString* templates);
bool SecureDNSIsManaged();
void SetSecureDNSHandler(void (^handler)(void));

// A pref of `profile` as JSON, nil when it has none of that name.
NSString* PreferenceJSON(Profile* profile, NSString* name);
bool SetPreferenceJSON(Profile* profile, NSString* name, NSString* json);
bool ResetPreference(Profile* profile, NSString* name);

void SetProfileLoadedHandler(void (^handler)(NSString* path));
void SetExtensionSettingsHandler(void (^handler)(void));

// Quitting: no more handler calls.
void StopProfilePrefs();

}  // namespace cra

#endif  // CRA_PROFILE_PREFS_H_
