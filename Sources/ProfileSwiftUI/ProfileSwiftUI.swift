//
//  ProfileSwiftUI.swift
//  ProfileSwiftUI
//
//  Created by John Holdsworth on 28/03/2024.
//

#if canImport(Darwin) // Apple platforms only..
import Foundation
import SwiftRegex
@_exported 
import SwiftTrace
import DLKitC

public struct ProfileSwiftUI {
    
    /** framework to intercept */
    public static var packageFilter = "/SwiftUI.framework/"
    /** image number of framework to intercept */
    public static var targetImageNumber: UInt32 = 0
    /** Caller information extractor */
    public static var relevantRegex = #"( closure #\d+|in \S+ : some|AG\w+)"#
    /** methods to include */
    public static var inclusions = NSRegularExpression(regexp:
        #"^AG| -> |body\.getter"#)
    /** demangled symbols to avoid */
    public static var exclusions = NSRegularExpression(regexp:
        #"descriptor|default argument|infix|subscript|-> (some|SwiftUI\.(Text|Font))|AGAttributeNil|callerTotals\.modify"#)
    /* detail for end of symbol */
    public static var detailFormat = " 0x%llx%s"
    
    /** symbols to remap into package */
    public static var diversions = [
        "$s7SwiftUI15DynamicPropertyPAAE6updateyyF":
            "$s7SwiftUI15DynamicPropertyP07ProfileaB0E8__updateyyF"
    ]
    
    @discardableResult
    static func setTarget(framework: String) -> UInt32 {
        packageFilter = "/\(framework).framework/"
        targetImageNumber = (0..<_dyld_image_count()).first(where: {
            strstr(_dyld_get_image_name($0), packageFilter) != nil })!
        return targetImageNumber
    }
    
    public static func profile(interval: TimeInterval = 10, top: Int = 10,
                               methodPattern: String = #"\.getter"#) {
        SwiftTrace.startNewTrace(subLevels: 0)
        #if false
        var diversions = [rebinding]()
        for (from, to) in Self.diversions {
            guard let replacement = dlsym(SwiftMeta.RTLD_SELF, to) else { continue }
//            print(from, to)
            diversions.append(rebinding(name: strdup(from),
                replacement: replacement, replaced: nil))
        }
//        _ = SwiftTrace.apply(rebindings: &diversions)
//        SwiftTrace.initialRebindings += diversions
        #endif
        _ = SwiftTrace.interpose(aBundle: searchBundleImages(), methodName: methodPattern)
        let tracer: STTracer = { existing, symname in
            var info = Dl_info()
            guard existing >= _dyld_get_image_header(ProfileSwiftUI.targetImageNumber) &&
                    ProfileSwiftUI.targetImageNumber+1 < _dyld_image_count() &&
                    existing < _dyld_get_image_header(ProfileSwiftUI.targetImageNumber+1) ||
                    trie_dladdr(existing, &info) != 0 && strstr(info.dli_fname,
                        ProfileSwiftUI.packageFilter) != nil else { return existing }
            let demangled = SwiftMeta.demangle(symbol: symname) ?? String(cString: symname)+"()"
//            if demangled.contains("") || true {
//                print(String(cString: framework), demangled)
//            }
//            print("|"+demangled, terminator: "")
//            print(demangled)
            guard Self.diversions.index(forKey: String(cString: symname)) == nil,
                  ProfileSwiftUI.inclusions.matches(demangled),
                  !ProfileSwiftUI.exclusions.matches(demangled) else {
                return existing
            }
            let tracer: UnsafeMutableRawPointer = autoBitCast(SwiftTrace.Profile(name: demangled,
                          original: autoBitCast(existing))?.forwardingImplementation)
            SwiftTrace.initialRebindings.append(rebinding(name: symname,
                                                  replacement: tracer, replaced: nil))
            return tracer
        }
        
        let swiftUIImage = setTarget(framework: "SwiftUI")
        appBundleImages { path, header, slide in
            rebind_symbols_trace(autoBitCast(header), slide, tracer)
        }
        setTarget(framework: "AttributeGraph")
        rebind_symbols_trace(autoBitCast(_dyld_get_image_header(swiftUIImage)),
                             _dyld_get_image_vmaddr_slide(swiftUIImage),
                             tracer)
        _ = SwiftMeta.structsPassedByReference
        pollStats(interval: interval, top: top)
    }
    
    public static func pollStats(interval: TimeInterval = 10, top: Int = 10,
                                 detail: Int = 5, reset: Bool = true) {
        DispatchQueue.main.asyncAfter(deadline: .now()+interval) {
            print("\n⏳Profiles\n===========")
            for (swizzle, elapsed, callerTotals) in SwiftTrace
                .sortedSwizzles(onlyFirst: top, reset: reset) {
                print(String(format: "%.3fms\t🍿%@ 0x%llx",
                             elapsed*1000, swizzle.signature,
                             swizzle.implementation))
                guard let callerTotals else { continue }
                var totals = [String: Double]()
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
                    totals[relevant.joined() +
                           String(format: detailFormat, uintptr_t(bitPattern: info.dli_saddr),
                                  strrchr(info.dli_fname, Int32(UInt8(ascii: "/")))),
                           default: 0] += t
                }

                for (relevant, t) in totals
                    .sorted(by: { $0.value > $1.value } ).prefix(detail) {
                    print(String(format: "  ↳ %.3f\t%@",
                                 t*1000, relevant))
                }
            }
            pollStats(interval: interval, top: top, detail: detail)
        }
    }
}

extension SwiftTrace {
    
    /**
     Sorted descending accumulated amount of time spent in each swizzled method.
     */
    public static func sortedSwizzles(onlyFirst: Int? = nil, reset: Bool)
        -> [(Swizzle, TimeInterval, [UnsafeRawPointer: TimeInterval]?)] {
        let sorted = lastSwiftTrace.activeSwizzles.map { $0.value }
            .sorted { $0.totalElapsed > $1.totalElapsed }
        let out = (onlyFirst != nil ? Array(sorted.prefix(onlyFirst!)) : sorted)
                .map { ($0, $0.totalElapsed, ($0 as? Profile)?.callerTotals) }
        if reset {
            for swizzle in sorted {
                swizzle.totalElapsed = 0
                (swizzle as? Profile)?.callerTotals.removeAll()
            }
        }
        return out
    }
    
    open class Profile: Decorated {
        
        open var callerTotals = [UnsafeRawPointer: TimeInterval]()
        
        open override func onExit(stack: inout ExitStack,
                                  invocation: Swizzle.Invocation) {
            callerTotals[invocation.returnAddress, default: 0] += invocation.elapsed
            super.onExit(stack: &stack, invocation: invocation)
        }
    }
}

#if false
import SwiftUI

@available(macOS 10.15, iOS 13.0, *)
extension SwiftUI.DynamicProperty {
    public mutating func __update() {
        print("HERE")
        self.update()
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension SwiftUI.LocalizedStringKey {
    public init(__stringLiteral: String) {
        self.init(stringLiteral: __stringLiteral)
    }
}

@available(macOS 10.15, iOS 13.0, *)
extension SwiftUI.ViewBuilder {
    public static func __buildExpression<A: SwiftUI.View>(_ a: A) -> A {
        return buildExpression(a)
    }
    public static func __buildBlock<A: SwiftUI.View>(_ a: A) -> A {
        return buildBlock(a)
    }
}
#endif

//@available(iOS 16.0, *)
//extension SwiftUI.Text {
//    init<A>(alignment: TextAlignment, spacing: ViewSpacing, content: () -> A) -> VStack<A> {
//        self.init(alignment: TextAlignment, spacing: ViewSpacing, content: content)
//    }
//}

#endif
