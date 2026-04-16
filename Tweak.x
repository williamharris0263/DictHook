#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "fishhook.h"

// ==========================================
// 1. 数据库密钥拦截部分 (使用 Fishhook)
// ==========================================
static int (*original_sqlite3_key)(void *db, const void *pKey, int nKey);

static int replaced_sqlite3_key(void *db, const void *pKey, int nKey) {
    if (nKey > 0 && pKey != NULL) {
        NSData *keyData = [NSData dataWithBytes:pKey length:nKey];
        NSString *keyString = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
        NSString *msg = [NSString stringWithFormat:@"[密钥抓取成功]\n明文: %@\nHex: %@", 
                        keyString ?: @"无法转为文本", keyData];
        
        // 复制到剪贴板并保存
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = msg;
        });
        
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        [msg writeToFile:[docPath stringByAppendingPathComponent:@"sqlcipher_key.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return original_sqlite3_key(db, pKey, nKey);
}

// ==========================================
// 2. HTML 内容拦截部分 (使用 Logos)
// ==========================================
static void saveDecryptedHTML(NSString *html, NSURL *baseURL, NSString *method) {
    if (!html || html.length == 0) return;

    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *saveDir = [docPath stringByAppendingPathComponent:@"DecryptedHTML"];
    [[NSFileManager defaultManager] createDirectoryAtPath:saveDir withIntermediateDirectories:YES attributes:nil error:nil];

    // 尝试从 baseURL 提取原始加密文件名
    NSString *originalFileName = @"UnknownContent";
    if (baseURL && baseURL.lastPathComponent) {
        originalFileName = baseURL.lastPathComponent;
    }

    // 生成新文件名：原始文件名 + 时间戳
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSString *finalName = [NSString stringWithFormat:@"%@_%ld.html", originalFileName, (long)now];
    NSString *filePath = [saveDir stringByAppendingPathComponent:finalName];

    [html writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[HTML 拦截] 已保存: %@", finalName);
}

%hook WKWebView

- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL {
    saveDecryptedHTML(string, baseURL, @"loadHTMLString");
    return %orig(string, baseURL);
}

- (WKNavigation *)loadData:(NSData *)data MIMEType:(NSString *)MIMEType characterEncodingName:(NSString *)encoding baseURL:(NSURL *)baseURL {
    if ([MIMEType containsString:@"html"]) {
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        saveDecryptedHTML(html, baseURL, @"loadData");
    }
    return %orig(data, MIMEType, encoding, baseURL);
}

%end

// ==========================================
// 3. 初始化 (构造函数)
// ==========================================
%ctor {
    // 数据库密钥 Hook
    struct rebinding sql_reb;
    sql_reb.name = "sqlite3_key";
    sql_reb.replacement = (void *)replaced_sqlite3_key;
    sql_reb.replaced = (void **)&original_sqlite3_key;
    
    rebind_symbols((struct rebinding[1]){sql_reb}, 1);
    
    NSLog(@"[Dylib 合并版] 数据库与 HTML 拦截器已就绪");
}
