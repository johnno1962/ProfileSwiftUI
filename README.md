# ⏳Profile calls to SwiftUI

ProfileSwiftUI gives you improved visibility of where CPU is being
consumed inside your SwiftUI app. To use, add the ProfileSwiftUI 
Swift Package then import it and put something like the following 
in your RootView to setup logging then start polling statistics:

```
init() {
    ProfileSwiftUI.profile(interval: 10, top: 5)
}
```
Output is rather verbose as it also logs calls SwiftUI makes
internally to the "AttributeGraph" framework on which SwiftUI
is based though these can be filtered out by passing a regex.
(they will still appear in the periodic profile summary). The
output is grouped by the function being called with detail
entries breaking down where the function was called from.

## How it works.

At the interface between your app and the SwiftUI framework, methods
inside SwiftUI are dispatched indirectly through a form of lookup
using a writable area of memory (this is the standard means by which
the Darwin dynamic linker "binds" between frameworks). Using the
[fishhook](https://github.com/facebook/fishhook) library is is 
possible to update this dispatch table by symbol name and "rebind" 
or "interpose" any implementation you would like of these functions.

The [SwiftTrace](https://github.com/johnno1962/SwiftTrace) library
allows you to generate a logging aspect (trampoline) around each 
function call which you can interpose these to take the place of the
original call destination. To log calls to AttributeGraph a second
set of interposes is made on the SwiftUI libray where it calls out.
For whatever reason this second interpose only works in the simulator.
