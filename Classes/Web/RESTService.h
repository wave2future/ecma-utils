#import <Foundation/Foundation.h>

extern const NSString *WebServiceErrorKey;
extern const NSString *RequestStatusCode;

@interface RESTService : NSObject {
	NSString *baseUrl;
	NSString *locale;
}

- (id)initWithBaseUrl:(NSString*)url locale:(NSString*)locale;
- (id)post:(NSData*)data to:(NSString*)localPath error:(NSError**)error;
- (id)get:(NSString*)localPath withParams:(NSDictionary*)params error:(NSError**)error;

@end