#ifndef private_header_h
#define private_header_h

#import <ApplicationServices/ApplicationServices.h>

CF_ASSUME_NONNULL_BEGIN

AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

CF_ASSUME_NONNULL_END

#endif
