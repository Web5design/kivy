'''
ImageIO OSX framework
=====================

'''

__all__ = ('ImageLoaderImageIO', )

from kivy.logger import Logger
from . import ImageLoaderBase, ImageData, ImageLoader

from array import array
from libcpp cimport bool
from libc.stdlib cimport malloc, free
from libc.string cimport memcpy

ctypedef unsigned long size_t
ctypedef signed long CFIndex

cdef extern from "stdlib.h":
    void* calloc(size_t, size_t)

cdef extern from "Python.h":
    object PyString_FromStringAndSize(char *s, Py_ssize_t len)

cdef extern from "CoreGraphics/CGDataProvider.h":
    ctypedef void *CFDataRef
    unsigned char *CFDataGetBytePtr(CFDataRef)
    ctypedef void *CGDataProviderRef
    CFDataRef CGDataProviderCopyData(CGDataProviderRef)
    ctypedef void *CGDataProviderRef
    CFDataRef CGDataProviderCopyData(CGDataProviderRef)
    ctypedef void *CGImageRef
    CGDataProviderRef CGImageGetDataProvider(CGImageRef)
    size_t CGImageGetWidth(CGImageRef)
    size_t CGImageGetHeight(CGImageRef)
    size_t CGImageGetBitsPerPixel(CGImageRef)
    int CGImageGetAlphaInfo(CGImageRef)
    int kCGImageAlphaNone
    int kCGImageAlphaNoneSkipLast
    int kCGImageAlphaNoneSkipFirst
    int kCGImageAlphaFirst
    int kCGImageAlphaLast
    int kCGImageAlphaPremultipliedLast
    int kCGImageAlphaPremultipliedFirst
    int kCGBitmapByteOrder32Host

    ctypedef void *CGColorSpaceRef
    CGColorSpaceRef CGImageGetColorSpace(CGImageRef image)
    CGColorSpaceRef CGColorSpaceCreateDeviceRGB()

    ctypedef void *CGContextRef
    void CGContextTranslateCTM(CGContextRef, float, float)
    void CGContextScaleCTM (CGContextRef, float, float)

    ctypedef struct CGPoint:
        float x
        float y

    ctypedef struct CGSize:
        float width
        float height

    ctypedef struct CGRect:
        CGPoint origin
        CGSize size

    CGRect CGRectMake(float, float, float, float)

    CGContextRef CGBitmapContextCreate(
       void *data,
       size_t width,
       size_t height,
       size_t bitsPerComponent,
       size_t bytesPerRow,
       CGColorSpaceRef colorspace,
       unsigned int bitmapInfo
    )

    void CGContextDrawImage(CGContextRef, CGRect, CGImageRef)
    int kCGBlendModeCopy
    void CGContextSetBlendMode(CGContextRef, int)


cdef extern from "CoreFoundation/CFBase.h":
    ctypedef void *CFAllocatorRef
    ctypedef void *CFStringRef
    ctypedef void *CFURLRef
    ctypedef void *CFTypeRef
    CFStringRef CFStringCreateWithCString (CFAllocatorRef alloc, char *cStr,
            int encoding)

    void CFRelease(CFTypeRef cf)

cdef unsigned int kCFStringEncodingUTF8 = 0x08000100

cdef extern CFStringRef kUTTypePNG

cdef extern from "CoreFoundation/CFURL.h":
    ctypedef void *CFURLRef
    ctypedef int CFURLPathStyle
    int kCFURLPOSIXPathStyle
    CFAllocatorRef kCFAllocatorDefault
    CFURLRef CFURLCreateFromFileSystemRepresentation(
            CFAllocatorRef, unsigned char *, CFIndex, bool)
    CFURLRef CFURLCreateWithFileSystemPath(CFAllocatorRef allocator,
            CFStringRef filePath, CFURLPathStyle pathStyle, int isDirectory)

cdef extern from "CoreFoundation/CFDictionary.h":
    ctypedef void *CFDictionaryRef

cdef extern from "CoreGraphics/CGImage.h":
    ctypedef void *CGImageRef
    CGDataProviderRef CGImageGetDataProvider(CGImageRef)
    int CGImageGetAlphaInfo(CGImageRef)
    int kCGImageAlphaNone

cdef extern from "CoreGraphics/CGBitmapContext.h":
    CGImageRef CGBitmapContextCreateImage(CGColorSpaceRef)

cdef extern from "ImageIO/CGImageSource.h":
    ctypedef void *CGImageSourceRef
    CGImageSourceRef CGImageSourceCreateWithURL(
            CFURLRef, CFDictionaryRef)
    CGImageRef CGImageSourceCreateImageAtIndex(
            CGImageSourceRef, size_t, CFDictionaryRef)

cdef extern from "ImageIO/CGImageDestination.h":
    ctypedef void *CGImageDestinationRef
    CGImageDestinationRef CGImageDestinationCreateWithURL(
        CFURLRef, CFStringRef, size_t, CFDictionaryRef)
    void CGImageDestinationAddImage (CGImageDestinationRef idst,
        CGImageRef image, CFDictionaryRef properties)
    int CGImageDestinationFinalize (CGImageDestinationRef idst)


def load_image_data(bytes _url):
    cdef CFURLRef url
    url = CFURLCreateFromFileSystemRepresentation(NULL, <bytes> _url, len(_url), 0)
    cdef CGImageSourceRef myImageSourceRef = CGImageSourceCreateWithURL(url, NULL)
    cdef CGImageRef myImageRef = CGImageSourceCreateImageAtIndex (myImageSourceRef, 0, NULL)
    cdef size_t width = CGImageGetWidth(myImageRef)
    cdef size_t height = CGImageGetHeight(myImageRef)
    cdef CGRect rect = CGRectMake(0, 0, width, height)
    cdef void * myData = calloc(width * 4, height)
    cdef CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB()

    # endianness:  kCGBitmapByteOrder32Little = (2 << 12)
    # (2 << 12) | kCGImageAlphaPremultipliedLast)
    cdef CGContextRef myBitmapContext = CGBitmapContextCreate(
            myData, width, height, 8, width*4, space,
            kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst)

    # This is necessary as the image would be vertically flipped otherwise
    CGContextTranslateCTM(myBitmapContext, 0, height)
    CGContextScaleCTM(myBitmapContext, 1, -1)

    CGContextSetBlendMode(myBitmapContext, kCGBlendModeCopy)
    CGContextDrawImage(myBitmapContext, rect, myImageRef)
    #CGContextRelease(myBitmapContext)

    r_data = PyString_FromStringAndSize(<char *> myData, width * height * 4)

    # XXX
    # kivy doesn't like to process 'bgra' data. we swap manually to 'rgba'.
    # would be better to fix this in texture.pyx
    a = array('b', r_data)
    a[0::4], a[2::4] = a[2::4], a[0::4]
    r_data = a.tostring()
    imgtype = 'rgba'

    return (width, height, imgtype, r_data)

def save_image_rgba(filename, width, height, data):
    assert(len(data) == width * height * 4)

    print 'save rggba image: create the memory and copy', type(data), len(data)
    cdef char *source = NULL
    if type(data) is array:
        data = data.tostring()
    source = <bytes>data[:len(data)]

    print 'now malloc'
    cdef char *rgba = <char *>malloc(int(width * height * 4))
    print 'now copy'
    memcpy(rgba, <void *>source, int(width * height * 4))
    
    print 'XX create COLORSPACE'
    cdef CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB()
    print 'XX create BITMAP CONTEXT'
    cdef CGContextRef bitmapContext = CGBitmapContextCreate(
        rgba,
        width,
        height,
        8, # bitsPerComponent
        4 * width, # bytesPerRow
        colorSpace,
        kCGImageAlphaNoneSkipLast)

    print 'XX bitmap create image', <long>bitmapContext
    cdef CGImageRef cgImage = CGBitmapContextCreateImage(bitmapContext)
    print 'XX filename %r' % filename
    cdef char *cfilename = <char *>malloc(len(filename) + 1)
    memcpy(cfilename, <char *><bytes>filename, len(filename));
    cfilename[len(filename)] = <char>0
    cdef CFStringRef sfilename = CFStringCreateWithCString(NULL,
            cfilename, kCFStringEncodingUTF8)
    print '->', <long>sfilename
    print 'XX url'
    cdef CFURLRef url = CFURLCreateWithFileSystemPath(NULL,
            sfilename, kCFURLPOSIXPathStyle, 0)

    print '->', <long>url
    print 'XX create dest'
    cdef CFStringRef ctype = kUTTypePNG
    cdef CGImageDestinationRef dest = CGImageDestinationCreateWithURL(url,
            ctype, 1, NULL)

    print 'XX add image'
    CGImageDestinationAddImage(dest, cgImage, NULL)

    print 'XX release everthing'
    CFRelease(cgImage)
    CFRelease(bitmapContext)
    print 'XX release colorspace'
    CFRelease(colorSpace)

    print 'XX finalize'
    CGImageDestinationFinalize(dest)

class ImageLoaderImageIO(ImageLoaderBase):
    '''Image loader based on ImageIO MacOSX Framework
    '''

    @staticmethod
    def extensions():
        # FIXME check which one are available on osx
        return ('bmp', 'bufr', 'cur', 'dcx', 'fits', 'fl', 'fpx', 'gbr',
                'gd', 'gif', 'grib', 'hdf5', 'ico', 'im', 'imt', 'iptc',
                'jpeg', 'jpg', 'mcidas', 'mic', 'mpeg', 'msp', 'pcd',
                'pcx', 'pixar', 'png', 'ppm', 'psd', 'sgi', 'spider',
                'tga', 'tiff', 'wal', 'wmf', 'xbm', 'xpm', 'xv')

    def load(self, filename):
        # FIXME: if the filename is unicode, the loader is failing.
        ret = load_image_data(str(filename))
        if ret is None:
            Logger.warning('Image: Unable to load image <%s>' % filename)
            raise Exception('Unable to load image')
        w, h, imgtype, data = ret
        return (ImageData(w, h, imgtype, data), )

# register
ImageLoader.register(ImageLoaderImageIO)