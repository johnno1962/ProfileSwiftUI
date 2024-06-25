//
//  ProfileSwiftUI.swift
//  ProfileSwiftUI
//
//  Created by John Holdsworth on 28/03/2024.
//

#if DEBUG || !SWIFT_PACKAGE
#if canImport(Darwin) // Apple platforms only..
import Foundation
#if SWIFT_PACKAGE
import SwiftTraceD
import SwiftRegex
import DLKitCD
#else
import SwiftTrace
#endif

public struct ProfileSwiftUI {
    
    /** framework to intercept  calls to*/
    public static var packageFilter = "/SwiftUI.framework/"
    /** image number of framework to intercept calls to */
    public static var targetImageNumber: UInt32 = 0
    /** Caller information extractor */
    public static var relevantRegex = #"( closure #\d+|in \S+ : some|AG\w+)"#
    /** Regex pattern for methods to add profiling aspect */
    public static var inclusions = NSRegularExpression(regexp:
        #"^AG| -> |body\.getter"#)
    /** demangled symbol names to avoid */
    public static var exclusions = NSRegularExpression(regexp:
        #"descriptor|default argument|infix|subscript|-> (some|SwiftUI\.(Text|Font))|AGAttributeNil|callerTotals\.modify"#)

    /** format for function summary entries */
    public static var entryFormat = "%10@\t🍿%@ 0x%llx"
    /** format for detail/caller entries */
    public static var detailFormat = "  ↳ %@\t%@"
    /** suffix for end of caller symbol */
    public static var suffixFormat = " 0x%llx%s"
    /** formats for displaying elapsed times/counts */
    public static var timeFormat = "%.3fms/%d"
    
    @discardableResult
    static func setTarget(framework: String) -> UInt32? {
        packageFilter = "/\(framework).framework/"
        guard let imageNumber = (UInt32(0)..<_dyld_image_count()).first(where: {
            strstr(_dyld_get_image_name($0), packageFilter) != nil }) else { return nil }
        targetImageNumber = imageNumber
        return targetImageNumber
    }
    
    static var tracer: STTracer = { existing, symname in
        var info = Dl_info()
        // Is the destinaton of the binding in the target image?
        guard existing >= autoBitCast(_dyld_get_image_header(ProfileSwiftUI.targetImageNumber)) &&
                ProfileSwiftUI.targetImageNumber+1 < _dyld_image_count() &&
                existing < autoBitCast(_dyld_get_image_header(ProfileSwiftUI.targetImageNumber+1)) ||
                trie_dladdr(existing, &info) != 0 && strstr(info.dli_fname,
                    ProfileSwiftUI.packageFilter) != nil else { return existing }
        let demangled = SwiftMeta.demangle(symbol: symname) ?? String(cString: symname)+"()"
        guard ProfileSwiftUI.inclusions.matches(demangled),
              !ProfileSwiftUI.exclusions.matches(demangled) else {
            return existing
        }
        // Construct logger aspect
        let tracer: UnsafeMutableRawPointer = autoBitCast(Profile(name: demangled,
                      original: autoBitCast(existing))?.forwardingImplementation)
        // Continue logging after "injections"
        SwiftTrace.initialRebindings.append(rebinding(name: symname,
                                              replacement: tracer, replaced: nil))
        return tracer
    }
    
    /// ProfileSwiftUI.profile() - log statistics on SwuiftUI log jams
    /// - Parameters:
    ///   - interval: Interval between sumping stats. nil == manual polling.
    ///   - top: # of functions to print stats for,
    ///   - detail: # number of callers to break down sstats for.
    ///   - reset: Whether to reset statistics between polls.
    ///   - methodPattern: Additional app methods to incldue stats for.
    ///   - traceFilter: Regex pattern for functions to log. Pass #"^(?!AG)"# to filter out AG
    public static func profile(interval: TimeInterval? = 10, top: Int = 10,
                               detail: Int = 5, reset: Bool = true,
                               methodPattern: String = #"\.getter"#,
                               traceFilter: String? = nil) {
        SwiftTrace.startNewTrace(subLevels: 0)
        // Filter out messages?
        if let filter = traceFilter {
            SwiftTrace.traceFilterInclude = filter
        }
        // Includ elogging on all app methods matching pattern
        _ = SwiftTrace.interpose(aBundle: searchBundleImages(), methodName: methodPattern)
        
        guard let swiftUIImage = setTarget(framework: "SwiftUI") else {
            print("⏳ SwiftUI not in use.")
            return
        }
        print("⏳ Logging all calls from App into SwiftUI.")
        appBundleImages { path, header, slide in
            rebind_symbols_trace(autoBitCast(header), slide, tracer)
        }
        
        print("⏳ Logging all calls from SwiftUI into the AttributeGraph framework.")
        setTarget(framework: "AttributeGraph")
        rebind_symbols_trace(autoBitCast(_dyld_get_image_header(swiftUIImage)),
                             _dyld_get_image_vmaddr_slide(swiftUIImage),
                             tracer)
        
        _ = SwiftMeta.structsPassedByReference // perform ahead of time.
        // Start polling
        if interval != nil {
            pollStats(interval: interval, top: top, detail: detail, reset: reset)
        }
    }
    
    public static func pollStats(interval: TimeInterval? = 10, top: Int = 10,
                                 detail: Int = 5, reset: Bool = true) {
        DispatchQueue.main.asyncAfter(deadline: .now()+(interval ?? 0)) {
            print("\n⏳Profiles\n===========")
            func usecFormat(_ elapsed: TimeInterval, _ count: Int) -> String {
                return String(format: timeFormat, elapsed * 1000.0, count)
            }
            for (swizzle, elapsed, callerTotals, callerCounts)
                    in sortedSwizzles(onlyFirst: top, reset: reset) {
                var total = 0, totals = [String: Double](), counts = [String: Int]()
                var info = Dl_info()
                for (caller, t) in callerTotals
                    .sorted(by: { $0.value > $1.value } ) {
                    guard trie_dladdr(caller, &info) != 0, let sym = info.dli_sname else { continue }
                    let callerDecl = SwiftMeta.demangle(symbol: sym) ?? String(cString: sym)
//                        print(callerDecl)
                    var relevant: [String] = callerDecl[relevantRegex]
                    if !relevant.isEmpty {
                        relevant = relevant.suffix(1)+relevant.dropLast()
                    } else {
                        relevant = [callerDecl]
                    }
                    let key = relevant.joined() +
                        String(format: suffixFormat, uintptr_t(bitPattern: info.dli_saddr),
                               strrchr(info.dli_fname, Int32(UInt8(ascii: "/"))))
                    totals[key, default: 0] += t
                    let count = callerCounts[caller] ?? 0
                    counts[key, default: 0] += count
                    total += count
                }

                #if swift(>=5.10)
                totals = totals // Needed for Xcode 15.3!
                #endif
                print(String(format: entryFormat, usecFormat(elapsed, total),
                             swizzle.signature, swizzle.implementation))
                for (relevant, t) in totals
                    .sorted(by: { $0.value > $1.value } ).prefix(detail) {
                    print(String(format: detailFormat,
                                 usecFormat(t, counts[relevant] ?? 0), relevant))
                }
            }
            
            if interval != nil {
                pollStats(interval: interval, top: top, detail: detail, reset: reset)
            }
        }
    }

    /**
     Sorted descending accumulated amount of time spent in each swizzled method.
     */
    public static func sortedSwizzles(onlyFirst: Int? = nil, reset: Bool) ->
        [(SwiftTrace.Swizzle, TimeInterval,
          [UnsafeRawPointer: TimeInterval], [UnsafeRawPointer: Int])] {
        let sorted = SwiftTrace.lastSwiftTrace.activeSwizzles.map { $0.value }
            .sorted { $0.totalElapsed > $1.totalElapsed }
        let out = (onlyFirst != nil ? Array(sorted.prefix(onlyFirst!)) : sorted)
            .compactMap { $0 as? Profile }.map {
                return ($0, $0.totalElapsed, $0.callerTotals, $0.callerCounts) }
        if reset {
            for swizzle in sorted {
                swizzle.totalElapsed = 0
                guard let profile = swizzle as? Profile else { continue }
                profile.callerTotals.removeAll()
                profile.callerCounts.removeAll()
            }
        }
        return out
    }
    
    open class Profile: SwiftTrace.Decorated {
        
        open var callerCounts = [UnsafeRawPointer: Int]()
        open var callerTotals = [UnsafeRawPointer: TimeInterval]()
        
        open override func onExit(stack: inout SwiftTrace.ExitStack,
                                  invocation: SwiftTrace.Swizzle.Invocation) {
            callerTotals[invocation.returnAddress, default: 0] += invocation.elapsed
            callerCounts[invocation.returnAddress, default: 0] += 1
            super.onExit(stack: &stack, invocation: invocation)
        }
    }
}

extension Dl_info: CustomDebugStringConvertible {
    public var debugDescription: String {
        String(format: "0x%llx %@", uintptr_t(bitPattern: dli_saddr),
               SwiftMeta.demangle(symbol: dli_sname) ?? String(cString: dli_sname))
    }
}
#endif
#endif
