// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_google_places_sdk_ios",
    platforms: [
        .iOS("16.0"),
    ],
    products: [
        .library(name: "flutter-google-places-sdk-ios", targets: ["flutter_google_places_sdk_ios"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/googlemaps/ios-places-sdk", from: "10.15.0"),
    ],
    targets: [
        .target(
            name: "flutter_google_places_sdk_ios",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "GooglePlaces", package: "ios-places-sdk"),
            ]
        )
    ]
)
