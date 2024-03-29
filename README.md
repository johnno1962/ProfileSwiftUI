# Profile calls to SwiftUI

Add the ProfileSwiftUI Swift Package then import it and put something like the folllowing in your RootView:

```
init() {
    ProfileSwiftUI.profile(interval: 10, top: 5)
}
```
