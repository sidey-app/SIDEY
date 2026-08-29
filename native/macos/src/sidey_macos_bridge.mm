#include "sidey_macos_bridge.h"

#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string_name.hpp>

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <Security/Security.h>
#import <ServiceManagement/ServiceManagement.h>

using namespace godot;

namespace {

NSString *const kSideyKeychainService = @"com.sidey.desktop";
constexpr OSType kSideyHotkeySignature = 'SDY1';
constexpr UInt32 kComposeHotkeyId = 1;
constexpr UInt32 kToggleLockHotkeyId = 2;

NSString *to_ns_string(const String &value) {
	CharString utf8 = value.utf8();
	return [[NSString alloc] initWithBytes:utf8.get_data()
								length:static_cast<NSUInteger>(utf8.length())
							  encoding:NSUTF8StringEncoding];
}

String to_godot_string(NSString *value) {
	if (value == nil) {
		return String();
	}
	return String::utf8(value.UTF8String);
}

Error keychain_status_to_error(OSStatus status) {
	switch (status) {
		case errSecSuccess:
			return OK;
		case errSecItemNotFound:
			return ERR_DOES_NOT_EXIST;
		case errSecAuthFailed:
		case errSecInteractionNotAllowed:
			return ERR_UNAUTHORIZED;
		case errSecDuplicateItem:
			return ERR_ALREADY_EXISTS;
		default:
			return FAILED;
	}
}

OSStatus sidey_hotkey_handler(EventHandlerCallRef, EventRef event, void *user_data) {
	EventHotKeyID hotkey_id = {};
	OSStatus status = GetEventParameter(
		event,
		kEventParamDirectObject,
		typeEventHotKeyID,
		nullptr,
		sizeof(hotkey_id),
		nullptr,
		&hotkey_id
	);
	if (status == noErr && hotkey_id.signature == kSideyHotkeySignature && user_data != nullptr) {
		auto *bridge = static_cast<sidey::SideyMacOSBridge *>(user_data);
		bridge->call_deferred("dispatch_hotkey", static_cast<int>(hotkey_id.id));
	}
	return status;
}

} // namespace

namespace sidey {

SideyMacOSBridge::SideyMacOSBridge() {
	CFDictionaryRef session = CGSessionCopyCurrentDictionary();
	if (session != nullptr) {
		CFBooleanRef locked = static_cast<CFBooleanRef>(
			CFDictionaryGetValue(session, CFSTR("CGSSessionScreenIsLocked"))
		);
		screen_locked_ = locked != nullptr && CFBooleanGetValue(locked);
		CFRelease(session);
	}
}

SideyMacOSBridge::~SideyMacOSBridge() {
	unregister_hotkeys();
	unregister_workspace_observers();
}

void SideyMacOSBridge::_bind_methods() {
	ClassDB::bind_method(D_METHOD("capability_report"), &SideyMacOSBridge::capability_report);
	ClassDB::bind_method(D_METHOD("keychain_store", "account", "secret"), &SideyMacOSBridge::keychain_store);
	ClassDB::bind_method(D_METHOD("keychain_read", "account"), &SideyMacOSBridge::keychain_read);
	ClassDB::bind_method(D_METHOD("keychain_delete", "account"), &SideyMacOSBridge::keychain_delete);
	ClassDB::bind_method(D_METHOD("get_idle_seconds"), &SideyMacOSBridge::get_idle_seconds);
	ClassDB::bind_method(D_METHOD("is_screen_locked"), &SideyMacOSBridge::is_screen_locked);
	ClassDB::bind_method(D_METHOD("register_default_hotkeys"), &SideyMacOSBridge::register_default_hotkeys);
	ClassDB::bind_method(D_METHOD("unregister_hotkeys"), &SideyMacOSBridge::unregister_hotkeys);
	ClassDB::bind_method(D_METHOD("set_overlay_runtime_mode", "enabled"), &SideyMacOSBridge::set_overlay_runtime_mode);
	ClassDB::bind_method(D_METHOD("set_all_spaces_window_policy", "enabled"), &SideyMacOSBridge::set_all_spaces_window_policy);
	ClassDB::bind_method(D_METHOD("set_ignores_mouse_events", "enabled"), &SideyMacOSBridge::set_ignores_mouse_events);
	ClassDB::bind_method(D_METHOD("set_launch_at_login", "enabled"), &SideyMacOSBridge::set_launch_at_login);
	ClassDB::bind_method(D_METHOD("is_launch_at_login_enabled"), &SideyMacOSBridge::is_launch_at_login_enabled);
	ClassDB::bind_method(D_METHOD("dispatch_hotkey", "hotkey_id"), &SideyMacOSBridge::dispatch_hotkey);

	ADD_SIGNAL(MethodInfo("screen_lock_changed", PropertyInfo(Variant::BOOL, "locked")));
	ADD_SIGNAL(MethodInfo("system_sleep_changed", PropertyInfo(Variant::BOOL, "sleeping")));
	ADD_SIGNAL(MethodInfo("system_resumed"));
	ADD_SIGNAL(MethodInfo("global_shortcut_pressed", PropertyInfo(Variant::STRING_NAME, "action")));
}

void SideyMacOSBridge::_notification(int what) {
	if (what == NOTIFICATION_READY) {
		register_workspace_observers();
	} else if (what == NOTIFICATION_EXIT_TREE) {
		unregister_hotkeys();
		unregister_workspace_observers();
	}
}

Dictionary SideyMacOSBridge::capability_report() const {
	Dictionary report;
	report["native_bridge"] = true;
	report["secure_storage"] = true;
	report["system_idle_time"] = true;
	report["screen_lock_events"] = true;
	report["sleep_wake_events"] = true;
	report["global_shortcuts"] = true;
	report["launch_at_login"] = true;
	report["all_spaces_window_policy"] = true;
	report["dockless_activation_policy"] = true;
	return report;
}

Error SideyMacOSBridge::keychain_store(const String &account, const String &secret) {
	if (account.is_empty() || secret.is_empty()) {
		return ERR_INVALID_PARAMETER;
	}
	@autoreleasepool {
		NSString *account_value = to_ns_string(account);
		NSData *secret_data = [to_ns_string(secret) dataUsingEncoding:NSUTF8StringEncoding];
		NSDictionary *query = @{
			(__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
			(__bridge id)kSecAttrService : kSideyKeychainService,
			(__bridge id)kSecAttrAccount : account_value,
		};
		NSDictionary *update = @{(__bridge id)kSecValueData : secret_data};
		OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
		if (status == errSecItemNotFound) {
			NSMutableDictionary *insert = [query mutableCopy];
			insert[(__bridge id)kSecValueData] = secret_data;
			insert[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
			status = SecItemAdd((__bridge CFDictionaryRef)insert, nullptr);
		}
		return keychain_status_to_error(status);
	}
}

String SideyMacOSBridge::keychain_read(const String &account) const {
	if (account.is_empty()) {
		return String();
	}
	@autoreleasepool {
		NSDictionary *query = @{
			(__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
			(__bridge id)kSecAttrService : kSideyKeychainService,
			(__bridge id)kSecAttrAccount : to_ns_string(account),
			(__bridge id)kSecReturnData : @YES,
			(__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitOne,
		};
		CFTypeRef result = nullptr;
		OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
		if (status != errSecSuccess || result == nullptr) {
			if (result != nullptr) {
				CFRelease(result);
			}
			return String();
		}
		NSData *data = (__bridge_transfer NSData *)result;
		NSString *secret = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		return to_godot_string(secret);
	}
}

Error SideyMacOSBridge::keychain_delete(const String &account) {
	if (account.is_empty()) {
		return ERR_INVALID_PARAMETER;
	}
	@autoreleasepool {
		NSDictionary *query = @{
			(__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
			(__bridge id)kSecAttrService : kSideyKeychainService,
			(__bridge id)kSecAttrAccount : to_ns_string(account),
		};
		return keychain_status_to_error(SecItemDelete((__bridge CFDictionaryRef)query));
	}
}

double SideyMacOSBridge::get_idle_seconds() const {
	return CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
}

bool SideyMacOSBridge::is_screen_locked() const {
	return screen_locked_;
}

Error SideyMacOSBridge::register_default_hotkeys() {
	if (!hotkey_refs_.empty()) {
		return OK;
	}
	EventTypeSpec event_type = {kEventClassKeyboard, kEventHotKeyPressed};
	EventHandlerRef handler = nullptr;
	OSStatus status = InstallApplicationEventHandler(
		NewEventHandlerUPP(sidey_hotkey_handler),
		1,
		&event_type,
		this,
		&handler
	);
	if (status != noErr) {
		return FAILED;
	}
	hotkey_handler_ = handler;
	struct HotkeySpec {
		UInt32 key_code;
		UInt32 modifiers;
		UInt32 id;
	};
	const HotkeySpec specs[] = {
		{kVK_Space, cmdKey | shiftKey, kComposeHotkeyId},
		{kVK_ANSI_L, cmdKey | optionKey, kToggleLockHotkeyId},
	};
	for (const HotkeySpec &spec : specs) {
		EventHotKeyID hotkey_id = {kSideyHotkeySignature, spec.id};
		EventHotKeyRef hotkey_ref = nullptr;
		status = RegisterEventHotKey(
			spec.key_code,
			spec.modifiers,
			hotkey_id,
			GetApplicationEventTarget(),
			0,
			&hotkey_ref
		);
		if (status != noErr) {
			unregister_hotkeys();
			return ERR_ALREADY_IN_USE;
		}
		hotkey_refs_.push_back(hotkey_ref);
	}
	return OK;
}

void SideyMacOSBridge::unregister_hotkeys() {
	for (void *reference : hotkey_refs_) {
		if (reference != nullptr) {
			UnregisterEventHotKey(static_cast<EventHotKeyRef>(reference));
		}
	}
	hotkey_refs_.clear();
	if (hotkey_handler_ != nullptr) {
		RemoveEventHandler(static_cast<EventHandlerRef>(hotkey_handler_));
		hotkey_handler_ = nullptr;
	}
}

Error SideyMacOSBridge::set_overlay_runtime_mode(bool enabled) {
	@autoreleasepool {
		[NSApp setActivationPolicy:enabled ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular];
	}
	return set_all_spaces_window_policy(enabled);
}

Error SideyMacOSBridge::set_all_spaces_window_policy(bool enabled) {
	NSWindow *window = (__bridge NSWindow *)native_window();
	if (window == nil) {
		return ERR_UNAVAILABLE;
	}
	@autoreleasepool {
		NSWindowCollectionBehavior behavior = window.collectionBehavior;
		if (enabled) {
			behavior |= NSWindowCollectionBehaviorCanJoinAllSpaces;
			behavior |= NSWindowCollectionBehaviorFullScreenAuxiliary;
			behavior |= NSWindowCollectionBehaviorStationary;
			behavior &= ~NSWindowCollectionBehaviorMoveToActiveSpace;
			window.hidesOnDeactivate = NO;
		} else {
			behavior &= ~NSWindowCollectionBehaviorCanJoinAllSpaces;
			behavior &= ~NSWindowCollectionBehaviorFullScreenAuxiliary;
			behavior &= ~NSWindowCollectionBehaviorStationary;
		}
		window.collectionBehavior = behavior;
	}
	return OK;
}

Error SideyMacOSBridge::set_ignores_mouse_events(bool enabled) {
	NSWindow *window = (__bridge NSWindow *)native_window();
	if (window == nil) {
		return ERR_UNAVAILABLE;
	}
	window.ignoresMouseEvents = enabled ? YES : NO;
	return OK;
}

Error SideyMacOSBridge::set_launch_at_login(bool enabled) {
	if (@available(macOS 13.0, *)) {
		NSError *error = nil;
		BOOL success = enabled
			? [[SMAppService mainAppService] registerAndReturnError:&error]
			: [[SMAppService mainAppService] unregisterAndReturnError:&error];
		return success ? OK : FAILED;
	}
	return ERR_UNAVAILABLE;
}

bool SideyMacOSBridge::is_launch_at_login_enabled() const {
	if (@available(macOS 13.0, *)) {
		return [SMAppService mainAppService].status == SMAppServiceStatusEnabled;
	}
	return false;
}

void SideyMacOSBridge::dispatch_hotkey(int hotkey_id) {
	switch (static_cast<UInt32>(hotkey_id)) {
		case kComposeHotkeyId:
			emit_signal("global_shortcut_pressed", StringName("compose"));
			break;
		case kToggleLockHotkeyId:
			emit_signal("global_shortcut_pressed", StringName("toggle_lock"));
			break;
		default:
			break;
	}
}

void SideyMacOSBridge::register_workspace_observers() {
	if (observer_tokens_ != nullptr) {
		return;
	}
	@autoreleasepool {
		NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
		NSMutableArray *tokens = [NSMutableArray array];
		auto add_observer = ^(NSNotificationName name, void (^handler)(NSNotification *)) {
			id token = [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:handler];
			[tokens addObject:token];
		};
		add_observer(NSWorkspaceSessionDidResignActiveNotification, ^(NSNotification *) {
			emit_screen_lock(true);
		});
		add_observer(NSWorkspaceSessionDidBecomeActiveNotification, ^(NSNotification *) {
			emit_screen_lock(false);
		});
		add_observer(NSWorkspaceWillSleepNotification, ^(NSNotification *) {
			emit_system_sleep(true);
		});
		add_observer(NSWorkspaceDidWakeNotification, ^(NSNotification *) {
			emit_system_sleep(false);
		});
		observer_tokens_ = (__bridge_retained void *)tokens;
	}
}

void SideyMacOSBridge::unregister_workspace_observers() {
	if (observer_tokens_ == nullptr) {
		return;
	}
	@autoreleasepool {
		NSMutableArray *tokens = (__bridge_transfer NSMutableArray *)observer_tokens_;
		NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
		for (id token in tokens) {
			[center removeObserver:token];
		}
		observer_tokens_ = nullptr;
	}
}

void SideyMacOSBridge::emit_screen_lock(bool locked) {
	if (screen_locked_ == locked) {
		return;
	}
	screen_locked_ = locked;
	emit_signal("screen_lock_changed", locked);
}

void SideyMacOSBridge::emit_system_sleep(bool sleeping) {
	if (sleeping_ == sleeping) {
		return;
	}
	sleeping_ = sleeping;
	emit_signal("system_sleep_changed", sleeping);
	if (!sleeping) {
		emit_signal("system_resumed");
	}
}

void *SideyMacOSBridge::native_window() const {
	DisplayServer *display_server = DisplayServer::get_singleton();
	if (display_server == nullptr) {
		return nullptr;
	}
	uint64_t handle = display_server->window_get_native_handle(DisplayServer::WINDOW_HANDLE, DisplayServer::MAIN_WINDOW_ID);
	return reinterpret_cast<void *>(handle);
}

} // namespace sidey
