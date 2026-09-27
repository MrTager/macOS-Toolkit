import AppKit
import Foundation

enum SMCHelperBridge {
    static let machServiceName = "local.toolkit.smchelper"

    static func install() -> Bool {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices/local.toolkit.smchelper")
        guard FileManager.default.fileExists(atPath: helperURL.path) else {
            NSLog("helper binary missing in app bundle")
            return false
        }
        let script = """
        launchctl bootout system/local.toolkit.smchelper 2>/dev/null || true
        rm -f /Library/LaunchDaemons/local.toolkit.smchelper.plist /Library/PrivilegedHelperTools/local.toolkit.smchelper
        cp '\(helperURL.path)' /Library/PrivilegedHelperTools/local.toolkit.smchelper
        chmod 755 /Library/PrivilegedHelperTools/local.toolkit.smchelper
        chown root:wheel /Library/PrivilegedHelperTools/local.toolkit.smchelper
        cat > /Library/LaunchDaemons/local.toolkit.smchelper.plist <<'PLIST'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>local.toolkit.smchelper</string>
        <key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/local.toolkit.smchelper</string></array>
        <key>MachServices</key><dict><key>local.toolkit.smchelper</key><true/></dict>
        <key>RunAtLoad</key><true/>
        </dict></plist>
        PLIST
        chown root:wheel /Library/LaunchDaemons/local.toolkit.smchelper.plist
        chmod 644 /Library/LaunchDaemons/local.toolkit.smchelper.plist
        launchctl bootstrap system /Library/LaunchDaemons/local.toolkit.smchelper.plist
        exit 0
        """
        return runAsAdmin(script, prompt: "macOS Toolkit 需要安装 SMC 特权助手以读取温度与控制风扇")
    }

    static func uninstall() {
        _ = runAsAdmin(
            "launchctl bootout system/local.toolkit.smchelper 2>/dev/null; rm -f /Library/LaunchDaemons/local.toolkit.smchelper.plist /Library/PrivilegedHelperTools/local.toolkit.smchelper; exit 0",
            prompt: "移除 SMC 特权助手"
        )
    }

    @discardableResult
    private static func runAsAdmin(_ script: String, prompt: String) -> Bool {
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let osa = "do shell script \"\(escaped)\" with administrator privileges with prompt \"\(prompt)\""
        var error: NSDictionary?
        _ = NSAppleScript(source: osa)?.executeAndReturnError(&error)
        if let error {
            NSLog("admin script error: \(error)")
            return false
        }
        return true
    }

    static func ping() -> Bool {
        guard FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/local.toolkit.smchelper") else { return false }
        return call("ping", key: nil, data: nil) { reply in
            xpc_dictionary_get_int64(reply, "ok") == 1
        } ?? false
    }

    static func read(key: String) -> (type: String, size: Int, data: [UInt8])? {
        call("read", key: key, data: nil) { reply -> (String, Int, [UInt8])? in
            guard xpc_dictionary_get_int64(reply, "ok") == 1 else { return nil }
            guard let typeRaw = xpc_dictionary_get_string(reply, "type") else { return nil }
            let type = String(cString: typeRaw)
            let size = Int(xpc_dictionary_get_int64(reply, "size"))
            var length = 0
            guard let raw = xpc_dictionary_get_data(reply, "data", &length), length > 0 else { return nil }
            let bytePointer = raw.assumingMemoryBound(to: UInt8.self)
            let bytes = UnsafeBufferPointer(start: bytePointer, count: min(length, 32))
            return (type, size, Array(bytes))
        } ?? nil
    }

    static func write(key: String, data: [UInt8]) -> Bool {
        call("write", key: key, data: data) { reply in
            xpc_dictionary_get_int64(reply, "ok") == 1
        } ?? false
    }

    private static func call<T>(
        _ action: String,
        key: String?,
        data: [UInt8]?,
        parse: @escaping (xpc_object_t) -> T?
    ) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?

        let connection = xpc_connection_create_mach_service(
            machServiceName, nil, UInt64(XPC_CONNECTION_MACH_SERVICE_PRIVILEGED)
        )
        xpc_connection_set_event_handler(connection, { _ in })
        xpc_connection_resume(connection)

        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, "version", "1")
        xpc_dictionary_set_string(message, "action", action)
        if let key {
            xpc_dictionary_set_string(message, "key", key)
        }
        if let data {
            var mutable = data
            mutable.withUnsafeMutableBytes { raw in
                let pointer = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
                xpc_dictionary_set_data(message, "data", pointer, raw.count)
            }
        }

        xpc_connection_send_message_with_reply(connection, message, DispatchQueue.global()) { reply in
            if xpc_get_type(reply) == XPC_TYPE_DICTIONARY {
                result = parse(reply)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
        xpc_connection_cancel(connection)
        return result
    }
}
