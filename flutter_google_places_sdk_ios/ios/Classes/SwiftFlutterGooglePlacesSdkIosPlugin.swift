import Flutter
import UIKit
import GooglePlaces

public class SwiftFlutterGooglePlacesSdkIosPlugin: NSObject, FlutterPlugin {
    static let CHANNEL_NAME = "plugins.msh.com/flutter_google_places_sdk"
    let METHOD_INITIALIZE = "initialize"
    let METHOD_DEINITIALIZE = "deinitialize"
    let METHOD_IS_INITIALIZE = "isInitialized"
    let METHOD_FIND_AUTOCOMPLETE_PREDICTIONS = "findAutocompletePredictions"
    let METHOD_FETCH_PLACE = "fetchPlace"
    let METHOD_FETCH_PLACE_PHOTO = "fetchPlacePhoto"
    let METHOD_SEARCH_NEARBY = "searchNearby"
    
    private var placesClient: GMSPlacesClient!
    private var lastSessionToken: GMSAutocompleteSessionToken?
    
    private var photosCache: Dictionary<String, GMSPlacePhotoMetadata> = [:]
    private var runningUid: Int = 1

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: CHANNEL_NAME, binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterGooglePlacesSdkIosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case METHOD_INITIALIZE:
            let args = call.arguments as? Dictionary<String,Any>
            let apiKey = args?["apiKey"] as! String?
            // we can't do anything with the locale so no need to read it
            initialize(apiKey: apiKey)
            result(nil)
        case METHOD_DEINITIALIZE:
            // nothing to do
            result(nil)
        case METHOD_IS_INITIALIZE:
            result(placesClient != nil)
        case METHOD_FIND_AUTOCOMPLETE_PREDICTIONS:
            let args = call.arguments as! Dictionary<String,Any>
            let query = args["query"] as! String
            let countries = args["countries"] as? [String]? ?? [String]()
            let placeTypeFilters = args["typesFilter"] as? [String]
            let origin = latLngFromMap(argument: args["origin"] as? Dictionary<String, Any?>)
            let newSessionToken = args["newSessionToken"] as? Bool
            let locationBias = rectangularBoundsFromMap(argument: args["locationBias"] as? Dictionary<String, Any?>)
            let locationRestriction = rectangularBoundsFromMap(argument: args["locationRestriction"] as? Dictionary<String, Any?>)
            let sessionToken = getSessionToken(force: newSessionToken == true)
            
            // Create a type filter.
            let filter = GMSAutocompleteFilter()
            filter.types = placeTypeFilters;
            filter.countries = countries
            filter.origin = origin
            filter.locationBias = locationBias
            filter.locationRestriction = locationRestriction

            let request = GMSAutocompleteRequest(query: query)
            request.filter = filter
            request.sessionToken = sessionToken

            placesClient.fetchAutocompleteSuggestions(
                from: request,
                callback: { (results, error) in
                    if let error = error {
                        print("findAutoCompletePredictions error: \(error)")
                        result(FlutterError(
                            code: "API_ERROR",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    } else {
                        self.lastSessionToken = sessionToken
                        let mappedResult = self.responseToList(results: results)
                        result(mappedResult)
                    }
                })
        case METHOD_FETCH_PLACE:
            let args = call.arguments as! Dictionary<String,Any>
            let placeId = args["placeId"] as! String
            let properties = (args["fields"] as? [String])?.map {
                (item) in return placePropertyFromStr(it: item)
            } ?? [GMSPlaceProperty.all.rawValue]
            let newSessionToken = args["newSessionToken"] as? Bool ?? false
            let sessionToken = getSessionToken(force: newSessionToken == true)

            let request = GMSFetchPlaceRequest(
                placeID: placeId,
                placeProperties: properties,
                sessionToken: sessionToken
            )
            placesClient.fetchPlace(with: request) { (place, error) in
                if let error = error {
                    print("fetchPlace error: \(error)")
                    result(FlutterError(
                        code: "API_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                } else {
                    let mappedPlace = self.placeToMap(place: place)
                    result(mappedPlace)
                }
            }
        case METHOD_FETCH_PLACE_PHOTO:
            let args = call.arguments as! Dictionary<String,Any>
            let photoMetadataMap = args["photoMetadata"] as! Dictionary<String,Any>
            let photoRef = photoMetadataMap["photoReference"] as! String

            if let photoMetadata = photosCache[photoRef] {
                // maxSize from the metadata preserves the previous full-size behaviour of
                // loadPlacePhoto; the maxWidth/maxHeight args are still ignored, as before.
                let request = GMSFetchPhotoRequest(
                    photoMetadata: photoMetadata,
                    maxSize: photoMetadata.maxSize
                )
                placesClient.fetchPhoto(with: request, callback: { (photo, error) -> Void in
                    if let error = error {
                        print("fetchPlacePhoto error: \(error)")
                        result(FlutterError(
                            code: "API_ERROR_PHOTO",
                            message: error.localizedDescription,
                            details: nil
                        ))
                    } else {
                        let data = photo?.pngData()
                        result(data)
                    }
                })
            } else {
                result(FlutterError(
                    code: "API_ERROR_PHOTO",
                    message: "PhotoMetadata must be initially fetched with fetchPlace",
                    details: ""
                ))
            }
        case METHOD_SEARCH_NEARBY:
            let args = call.arguments as! Dictionary<String,Any>
            let properties = (args["fields"] as? [String])?.map {
                (item) in return placePropertyFromStr(it: item)
            } ?? [GMSPlaceProperty.all.rawValue]
            let locationRestriction = circularBoundsFromMap(argument: args["locationRestriction"] as? Dictionary<String, Any?>)
            let includedTypes = args["includedTypes"] as? [String]
            let includedPrimaryTypes = args["includedPrimaryTypes"] as? [String]
            let excludedTypes = args["excludedTypes"] as? [String]
            let excludedPrimaryTypes = args["excludedPrimaryTypes"] as? [String]
            let rankPreference = args["rankPreference"] as? String
            let regionCode = args["regionCode"] as? String
            let maxResultCount = args["maxResultCount"] as? Int

            guard let locationRestriction = locationRestriction else {
                result(FlutterError(
                    code: "API_ERROR",
                    message: "locationRestriction is required",
                    details: nil
                ))
                return
            }

            let request = GMSPlaceSearchNearbyRequest(locationRestriction: locationRestriction, placeProperties: properties)
            request.includedTypes = includedTypes ?? []
            request.includedPrimaryTypes = includedPrimaryTypes ?? []
            request.excludedTypes = excludedTypes ?? []
            request.excludedPrimaryTypes = excludedPrimaryTypes ?? []
            if let maxResultCount = maxResultCount {
                request.maxResultCount = maxResultCount
            }
            request.regionCode = regionCode
            if let rankPreference = rankPreference {
                if rankPreference == "DISTANCE" {
                    request.rankPreference = GMSPlaceSearchNearbyRankPreference.distance
                } else if rankPreference == "POPULARITY" {
                    request.rankPreference = GMSPlaceSearchNearbyRankPreference.popularity
                }
            }

            placesClient.searchNearby(with: request, completion: { (response, error) in
                if let error = error {
                    print("searchNearby error: \(error)")
                    result(FlutterError(
                        code: "API_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    ))
                } else {
                    let mappedPlaces = response?.places?.map { self.placeToMap(place: $0) }
                    result(mappedPlaces)
                }
            })
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func placeToMap(place: GMSPlace?) -> Dictionary<String, Any?> {
        guard let place = place else {
            return Dictionary<String, Any?>()
        }
        return [
            "address": place.formattedAddress,
            "addressComponents": place.addressComponents?.map { (it) in return addressComponentToMap(addressComponent: it) },
            "businessStatus": businessStatusToStr(it: place.businessStatus),
            "attributions": place.attributions,
            "latLng": latLngToMap(coordinate: place.coordinate),
            "name": place.name,
            "openingHours": openingHoursToMap(openingHours: place.openingHours),
            "phoneNumber": place.phoneNumber,
            "photoMetadatas": place.photos?.map { (it) in return photoMetadataToMap(photoMetadata: it) },
            "plusCode": plusCodeToMap(plusCode: place.plusCode),
            "priceLevel": place.priceLevel.rawValue,
            "rating": place.rating,
            "types": place.types?.map { (it) in return it.uppercased() },
            "userRatingsTotal": place.userRatingsTotal,
            "utcOffsetMinutes": place.utcOffsetMinutes,
            "viewport": latLngBoundsToMap(viewport: place.viewportInfo),
            "websiteUri": place.website?.absoluteString
        ]
    }
    
    private func businessStatusToStr(it: GMSPlacesBusinessStatus) -> String? {
        switch (it) {
        case GMSPlacesBusinessStatus.operational:
            return "OPERATIONAL";
        case GMSPlacesBusinessStatus.closedTemporarily:
            return "CLOSED_TEMPORARILY";
        case GMSPlacesBusinessStatus.closedPermanently:
            return "CLOSED_PERMANENTLY";
        default:
            return nil;
        }
    }
    
    private func plusCodeToMap(plusCode: GMSPlusCode?) -> Dictionary<String, Any?>? {
        guard let plusCode = plusCode else {
            return nil
        }
        
        return [
            "compoundCode": plusCode.compoundCode,
            "globalCode": plusCode.globalCode
        ]
    }
    
    private func photoMetadataToMap(photoMetadata: GMSPlacePhotoMetadata) -> Dictionary<String, Any?> {
        let photoRef = _getPhotoReference()
        
        photosCache[photoRef] = photoMetadata
        
        return [
            "photoReference": photoRef,
            "width": Int(photoMetadata.maxSize.width),
            "height": Int(photoMetadata.maxSize.height),
            "attributions": photoMetadata.attributions?.string
        ]
    }
    
    private func _getPhotoReference() -> String {
        let num = runningUid
        runningUid += 1
        return "id_" + String(num);
    }
    
    private func openingHoursToMap(openingHours: GMSOpeningHours?) -> Dictionary<String, Any?>? {
        guard let openingHours = openingHours else {
            return nil
        }
        return [
            "periods": openingHours.periods?.map { (it) in return periodToMap(period: it) },
            "weekdayText": openingHours.weekdayText
        ]
    }
    
    private func periodToMap(period: GMSPeriod) -> Dictionary<String, Any?> {
        return [
            "open": timeOfWeekToMap(event: period.openEvent),
            "close": timeOfWeekToMap(event: period.closeEvent)
        ]
    }
    
    private func timeOfWeekToMap(event: GMSEvent?) -> Dictionary<String, Any?>? {
        guard let event = event else {
            return nil
        }
        return [
            "day": dayOfWeekToStr(it: event.day),
            "time": placeLocalTimeToMap(time: event.time)
        ]
    }
    
    private func dayOfWeekToStr(it: GMSDayOfWeek) -> String {
        switch (it) {
        case GMSDayOfWeek.sunday: return "SUNDAY";
        case GMSDayOfWeek.monday: return "MONDAY";
        case GMSDayOfWeek.tuesday: return "TUESDAY";
        case GMSDayOfWeek.wednesday: return "WEDNESDAY";
        case GMSDayOfWeek.thursday: return "THURSDAY";
        case GMSDayOfWeek.friday: return "FRIDAY";
        case GMSDayOfWeek.saturday: return "SATURDAY";
        default: return "NULL";
        }
    }

    private func placeLocalTimeToMap(time: GMSTime) -> Dictionary<String, Any?> {
      return [
        "hours": time.hour,
        "minutes": time.minute
      ]
    }
    
    private func latLngToMap(coordinate: CLLocationCoordinate2D?) -> Any? {
        guard let coordinate = coordinate else {
            return nil
        }
        return [
            "lat": coordinate.latitude,
            "lng": coordinate.longitude
        ]
    }

    private func latLngBoundsToMap(viewport: GMSPlaceViewportInfo?) -> Dictionary<String, Any?>? {
        guard let viewport = viewport else {
            return nil
        }
        return [
            "southwest": latLngToMap(coordinate: viewport.southWest),
            "northeast": latLngToMap(coordinate: viewport.northEast)
        ]
    }

    private func addressComponentToMap(addressComponent: GMSAddressComponent) -> Dictionary<String, Any?> {
      return [
        "name": addressComponent.name,
        "shortName": addressComponent.shortName,
        "types": addressComponent.types
      ]
    }
    
    private func placePropertyFromStr(it: String) -> String {
        switch (it) {
        case "ADDRESS": return GMSPlaceProperty.formattedAddress.rawValue
        case "ADDRESS_COMPONENTS": return GMSPlaceProperty.addressComponents.rawValue
        case "BUSINESS_STATUS": return GMSPlaceProperty.businessStatus.rawValue
        case "ID": return GMSPlaceProperty.placeID.rawValue
        case "LAT_LNG": return GMSPlaceProperty.coordinate.rawValue
        case "NAME": return GMSPlaceProperty.name.rawValue
        case "OPENING_HOURS": return GMSPlaceProperty.openingHours.rawValue
        case "PHONE_NUMBER": return GMSPlaceProperty.phoneNumber.rawValue
        case "PHOTO_METADATAS": return GMSPlaceProperty.photos.rawValue
        case "PLUS_CODE": return GMSPlaceProperty.plusCode.rawValue
        case "PRICE_LEVEL": return GMSPlaceProperty.priceLevel.rawValue
        case "RATING": return GMSPlaceProperty.rating.rawValue
        case "TYPES": return GMSPlaceProperty.types.rawValue
        case "USER_RATINGS_TOTAL": return GMSPlaceProperty.userRatingsTotal.rawValue
        case "UTC_OFFSET": return GMSPlaceProperty.utcOffsetMinutes.rawValue
        case "VIEWPORT": return GMSPlaceProperty.viewport.rawValue
        case "WEBSITE_URI": return GMSPlaceProperty.website.rawValue
        default:
            fatalError("Invalid placeProperty: \(it)")
        }
    }
    
    private func responseToList(results: [GMSAutocompleteSuggestion]?) -> [Dictionary<String, Any?>]? {
        guard let results = results else {
            return nil;
        }

        // A suggestion whose placeSuggestion is nil carries no placeId and cannot be
        // represented in the Dart AutocompletePrediction contract, so it is dropped.
        return results.compactMap { (suggestion: GMSAutocompleteSuggestion) in
            guard let placeSuggestion = suggestion.placeSuggestion else {
                return nil
            }
            return placeSuggestionToMap(placeSuggestion: placeSuggestion) }
    }

    private func placeSuggestionToMap(placeSuggestion: GMSAutocompletePlaceSuggestion) -> Dictionary<String, Any?> {
        return [
            "placeId": placeSuggestion.placeID,
            "distanceMeters": placeSuggestion.distanceMeters,
            "primaryText": placeSuggestion.attributedPrimaryText.string,
            "secondaryText": placeSuggestion.attributedSecondaryText?.string ?? "",
            "fullText": placeSuggestion.attributedFullText.string,
            // placeTypes is intentionally omitted. The new autocomplete API returns
            // Places API (new) type vocabulary (e.g. "coffee_stand") that the Dart
            // PlaceType enum in flutter_google_places_sdk_platform_interface does not
            // know, and its fromJson throws ArgumentError on any unknown value --
            // failing the whole request. The Dart field is nullable and unused here.
            "placeTypes": nil
        ];
    }

    private func getSessionToken(force: Bool) -> GMSAutocompleteSessionToken! {
        let localToken = lastSessionToken
        if (force || localToken == nil) {
            return GMSAutocompleteSessionToken.init()
        }
        return localToken
    }
    
    private func rectangularBoundsFromMap(argument: Dictionary<String, Any?>?) -> (GMSPlaceLocationBias & GMSPlaceLocationRestriction)? {
        guard let argument = argument,
              let southWest = latLngFromMap(argument: argument["southwest"] as? Dictionary<String, Any?>)?.coordinate as? CLLocationCoordinate2D,
              let northEast = latLngFromMap(argument: argument["northeast"] as? Dictionary<String, Any?>)?.coordinate as? CLLocationCoordinate2D
               else {
            return nil
        }

        return GMSPlaceRectangularLocationOption(northEast, southWest);
    }

    private func circularBoundsFromMap(argument: Dictionary<String, Any?>?) -> GMSPlaceLocationRestriction? {
        guard let argument = argument,
              let center = latLngFromMap(argument: argument["center"] as? Dictionary<String, Any?>)?.coordinate as? CLLocationCoordinate2D,
              let radius = argument["radius"] as? Double else {
            return nil
        }

        return GMSPlaceCircularLocationOption(center, radius);
    }

    private func latLngFromMap(argument: Dictionary<String, Any?>?) -> CLLocation? {
        guard let argument = argument,
              let lat = argument["lat"] as? Double,
              let lng = argument["lng"] as? Double else {
            return nil
        }

        return CLLocation(latitude: lat, longitude: lng)
    }
    
    private func initialize(apiKey: String?) {
        GMSPlacesClient.provideAPIKey(apiKey ?? "")
        placesClient = GMSPlacesClient.shared()
    }
}
