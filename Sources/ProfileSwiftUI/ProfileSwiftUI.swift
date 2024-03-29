//
//  SwiftProfile.swift
//
//
//  Created by John Holdsworth on 28/03/2024.
//

#if canImport(Darwin) // Apple platforms only..
import Foundation
import SwiftRegex
@_exported 
import SwiftTrace

public struct ProfileSwiftUI {
    
    /** framework to intercept */
    public static var packageFilter = "/SwiftUI.framework/"
    /** Caller information extractor */
    public static var relevantRegex = #"( closure #\d+|in \S+ : some)"#
    /** demangled symbols to avoid */
    public static var exclusions = NSRegularExpression(regexp:
        #"descriptor|default argument|infix|subscript|-> some|SwiftUI\.(Text|Font)"#)
    /** symbols to remap into package */
    public static var diversions = [
        "$s7SwiftUI15DynamicPropertyPAAE6updateyyF":
            "$s7SwiftUI15DynamicPropertyP07ProfileaB0E8__updateyyF"
    ]
    
    open class Profile: SwiftTrace.Decorated {
        
        open var callerTotals = [UnsafeRawPointer: TimeInterval]()
        
        open override func onExit(stack: inout SwiftTrace.ExitStack,
                                  invocation: SwiftTrace.Swizzle.Invocation) {
            callerTotals[invocation.returnAddress, default: 0] += invocation.elapsed
            super.onExit(stack: &stack, invocation: invocation)
        }
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
        setSTInterposeHook({ existing, symname in
            var info = Dl_info()
            guard fast_dladdr(existing, &info) != 0 else { return existing }
            guard let framework = info.dli_fname,
                  strstr(framework, ProfileSwiftUI.packageFilter) != nil,
                  let demangled = SwiftMeta.demangle(symbol: symname) else { return existing }
//            if demangled.contains("build") {
//                print(String(cString: symname), demangled)
//            }
            guard demangled.contains(" -> ") || demangled.contains("body.getter"),
                  Self.diversions.index(forKey: String(cString: symname)) == nil,
                  !ProfileSwiftUI.exclusions.matches(demangled) else {
                return existing
            }
//            print(demangled)
            let tracer: UnsafeMutableRawPointer = autoBitCast(Profile(name: demangled,
                          original: autoBitCast(existing))?.forwardingImplementation)
            SwiftTrace.initialRebindings.append(rebinding(name: symname,
                                                  replacement: tracer, replaced: nil))
            return tracer
        })
        appBundleImages { path, header, slide in
            rebind_symbols_image(autoBitCast(header), slide, nil, -1)
        }
        //            _ = apply(rebindings: &rebindings)
        setSTInterposeHook(nil)
        _ = SwiftMeta.structsPassedByReference
        pollStats(interval: interval, top: top)
    }
    
    public static func pollStats(interval: TimeInterval = 10, top: Int = 10) {
        DispatchQueue.main.asyncAfter(deadline: .now()+interval) {
            print("\n⏳Profiles\n===========")
            for swizzle in sortedSwizzles(onlyFirst: top) {
                print(String(format: "%.3fms\t%@",
                             swizzle.totalElapsed*1000, swizzle.signature))
                guard let profile = swizzle as? Profile else { continue }
                var totals = [String: Double]()
                var info = Dl_info()
                for (caller, t) in profile.callerTotals
                    .sorted(by: { $0.value > $1.value } ) {
                    guard dladdr(caller, &info) != 0,
                          let callerDecl = SwiftMeta.demangle(symbol: info.dli_sname) else { continue }
//                        print(callerDecl)
                    var relevant: [String] = callerDecl[relevantRegex]
                    if relevant.isEmpty {
                        relevant = [callerDecl]
                    } else {
                        relevant = relevant.suffix(1)+relevant.dropLast()
                    }
                    totals[relevant.joined(), default: 0] += t
                }

                for (relevant, t) in totals
                    .sorted(by: { $0.value > $1.value } ) {
                    print(String(format: "  ↳ %.3f\t%@",
                                 t*1000, relevant))
                }
            }
            pollStats(interval: interval, top: top)
        }
    }
    
    /**
     Sorted descending accumulated amount of time spent in each swizzled method.
     */
    public static func sortedSwizzles(onlyFirst: Int? = nil) ->  [SwiftTrace.Swizzle] {
        let sorted = SwiftTrace.lastSwiftTrace.activeSwizzles.map { $0.value }
            .sorted { $0.totalElapsed > $1.totalElapsed }
        return onlyFirst != nil ? Array(sorted.prefix(onlyFirst!)) : sorted
    }
}

import SwiftUI

#if true
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
