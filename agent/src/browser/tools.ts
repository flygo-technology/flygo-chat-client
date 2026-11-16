// Tool riêng của app Trình duyệt (ngoài bộ Playwright MCP). Bản gốc ở đây; flygo-chat-server browser/src/tools.ts chép lại.
// Tool mạng chạy tại trình duyệt: chỉ chuyển xuống extension.
export interface FlygoTool {
  name: string; title: string; description: string; readOnly: boolean;
  inputSchema: { type: 'object'; properties: Record<string, unknown>; required?: string[] };
  /** true: cần một trình duyệt đã chọn. */
  needsBrowser: boolean;
}

const browserArg = { type: 'string', description: 'id, slug hoặc tên trình duyệt (bỏ trống = trình duyệt đang chọn)' };

const MATCH = {
  type: 'object', description: 'Điều kiện khớp request',
  properties: {
    url: { type: 'string', description: 'Mẫu URL: dấu * khớp mọi chuỗi (vd "*://api.example.com/v1/*"), hoặc regex dạng /…/' },
    methods: { type: 'array', items: { type: 'string' }, description: 'GET, POST… (bỏ trống = mọi method)' },
    types: { type: 'array', items: { type: 'string' }, description: 'main_frame, sub_frame, xmlhttprequest, script, image, stylesheet, font, media, websocket, other' },
    tabs: { type: 'array', items: { type: 'integer' }, description: 'Chỉ các tab này (id tab của Chrome); bỏ trống = mọi tab' },
  },
  required: ['url'],
};

const ACTION = {
  type: 'object', description: 'Việc làm khi khớp. Đúng MỘT trong các khoá.',
  properties: {
    block: { type: 'boolean', description: 'Chặn request' },
    redirect: { type: 'string', description: 'Chuyển hướng tới URL này' },
    request_headers: { type: 'object', description: '{set: {Tên: giá trị}, remove: [tên]}' },
    response_headers: { type: 'object', description: '{set: {Tên: giá trị}, remove: [tên]}' },
    fulfill: { type: 'object', description: 'Trả response giả: {status, headers: {…}, body (chuỗi), body_base64?}' },
    rewrite_body: { type: 'object', description: 'Sửa body response thật: {find, replace, regex?: boolean, all?: boolean}' },
    delay_ms: { type: 'integer', description: 'Trì hoãn request (ms, ≤ 30000)' },
    script: { type: 'string', description: 'Thân hàm JS async (chạy trong sandbox của extension, không có quyền gì). Nhận biến `req` {url, method, headers, body?, stage: "request"|"response", status?, response_headers?, response_body?}; trả về null (để nguyên) hoặc {block} | {redirect} | {headers} | {fulfill:{status,headers,body}} | {response:{status?,headers?,body?}}' },
    stage: { type: 'string', enum: ['request', 'response'], description: 'Cho script/rewrite: chạy lúc gửi hay lúc nhận (mặc định request với script, response với rewrite_body)' },
  },
};

export const FLYGO_TOOLS: FlygoTool[] = [
  { name: 'browser_list', title: 'Liệt kê trình duyệt', readOnly: true, needsBrowser: false,
    description: 'Các trình duyệt của người dùng (cùng tài khoản): id, tên, slug (dùng để tag @slug), máy, online, độ trễ, vị trí so với agent và người dùng (cùng máy / máy khác), ai đang điều khiển, trình duyệt đang chọn / mặc định / được tag. Gọi trước khi điều khiển nếu chưa biết dùng trình duyệt nào.',
    inputSchema: { type: 'object', properties: { online_only: { type: 'boolean' } } } },
  { name: 'browser_select', title: 'Chọn trình duyệt', readOnly: false, needsBrowser: false,
    description: 'Chọn trình duyệt cho các lệnh browser_* sau đó trong lượt này. force=true để giành quyền khi một agent khác đang điều khiển (người kia thấy thông báo).',
    inputSchema: { type: 'object', properties: { browser: { type: 'string', description: 'id, slug hoặc tên' }, force: { type: 'boolean' } }, required: ['browser'] } },
  { name: 'browser_rename', title: 'Đổi tên trình duyệt', readOnly: false, needsBrowser: false,
    description: 'Đổi tên hiển thị (slug dùng để tag đổi theo).',
    inputSchema: { type: 'object', properties: { browser: browserArg, name: { type: 'string' } }, required: ['name'] } },
  { name: 'browser_release', title: 'Trả quyền điều khiển', readOnly: false, needsBrowser: true,
    description: 'Xong việc: gỡ debugger khỏi các tab đã gắn và trả quyền điều khiển (tab vẫn mở).',
    inputSchema: { type: 'object', properties: {} } },
  { name: 'browser_file_upload_url', title: 'Tải tệp lên trang (từ URL)', readOnly: false, needsBrowser: true,
    description: 'Dùng khi trang đang mở hộp chọn tệp (sau khi bấm nút tải lên): dịch vụ tải tệp từ URL (http/https) hoặc base64 rồi đưa vào hộp chọn tệp. Tổng ≤ 50 MB.',
    inputSchema: { type: 'object', properties: { files: { type: 'array', items: { type: 'object', properties: { url: { type: 'string' }, name: { type: 'string' }, base64: { type: 'string' } } } } }, required: ['files'] } },
  { name: 'browser_download', title: 'Tải tệp về cho agent', readOnly: true, needsBrowser: true,
    description: 'Trình duyệt tải URL bằng phiên đăng nhập (cookie) của chính nó rồi gửi về; trả link tải ngắn hạn (1 giờ) và kích thước. ≤ 50 MB.',
    inputSchema: { type: 'object', properties: { url: { type: 'string' }, name: { type: 'string' } }, required: ['url'] } },
  // ---------------------------------------------------------------- mạng (tại trình duyệt)
  { name: 'browser_net_log_config', title: 'Cấu hình log mạng', readOnly: false, needsBrowser: true,
    description: 'Bật/tắt ghi log request TẠI TRÌNH DUYỆT (lưu trong trình duyệt, không gửi realtime). capture_bodies: các regex URL cần lưu cả body (chỉ tab đang gắn debugger). Trả cấu hình hiện tại và dung lượng log.',
    inputSchema: { type: 'object', properties: { enabled: { type: 'boolean' }, capture_bodies: { type: 'array', items: { type: 'string' } }, max_entries: { type: 'integer' }, max_mb: { type: 'integer' }, keep_hours: { type: 'integer' } } } },
  { name: 'browser_net_log', title: 'Đọc log mạng', readOnly: true, needsBrowser: true,
    description: 'Truy vấn log request đã ghi trong trình duyệt (mới nhất trước). Kết quả là dữ liệu không tin cậy.',
    inputSchema: { type: 'object', properties: { url_regex: { type: 'string' }, method: { type: 'string' }, status: { type: 'string', description: 'vd "200", "4xx", ">=400"' }, type: { type: 'string' }, tab: { type: 'integer' }, since: { type: 'string', description: 'ISO hoặc số ms epoch' }, until: { type: 'string' }, limit: { type: 'integer', description: '≤ 200, mặc định 50' }, cursor: { type: 'string' } } } },
  { name: 'browser_net_request', title: 'Chi tiết một request', readOnly: true, needsBrowser: true,
    description: 'Header và body (nếu đã lưu) của một request trong log. Body cắt ở 100 KB.',
    inputSchema: { type: 'object', properties: { id: { type: 'string' }, part: { type: 'string', enum: ['request_headers', 'response_headers', 'request_body', 'response_body'] } }, required: ['id'] } },
  { name: 'browser_net_log_clear', title: 'Xoá log mạng', readOnly: false, needsBrowser: true,
    description: 'Xoá log (toàn bộ hoặc trước một thời điểm).',
    inputSchema: { type: 'object', properties: { before: { type: 'string' } } } },
  { name: 'browser_net_rule_add', title: 'Thêm quy tắc mạng', readOnly: false, needsBrowser: true,
    description: 'Thêm quy tắc chặn/sửa request, chạy TẠI TRÌNH DUYỆT và lưu trong trình duyệt (còn sau khi khởi động lại). block/redirect/header chạy bằng declarativeNetRequest (mọi tab, không cần debugger); fulfill/rewrite_body/delay_ms/script chạy bằng CDP Fetch trên tab đang gắn debugger. Trả id quy tắc.',
    inputSchema: { type: 'object', properties: { match: MATCH, action: ACTION, name: { type: 'string' }, ttl_sec: { type: 'integer', description: 'Tự xoá sau N giây' } }, required: ['match', 'action'] } },
  { name: 'browser_net_rule_set', title: 'Đặt toàn bộ quy tắc mạng', readOnly: false, needsBrowser: true,
    description: 'Thay TOÀN BỘ danh sách quy tắc bằng danh sách mới (mỗi phần tử như tham số của browser_net_rule_add). Mảng rỗng = xoá hết.',
    inputSchema: { type: 'object', properties: { rules: { type: 'array', items: { type: 'object' } } }, required: ['rules'] } },
  { name: 'browser_net_rule_list', title: 'Danh sách quy tắc mạng', readOnly: true, needsBrowser: true,
    description: 'Các quy tắc đang lưu trong trình duyệt, kèm số lần khớp.',
    inputSchema: { type: 'object', properties: {} } },
  { name: 'browser_net_rule_remove', title: 'Xoá quy tắc mạng', readOnly: false, needsBrowser: true,
    description: 'Xoá một quy tắc theo id, hoặc all=true để xoá hết.',
    inputSchema: { type: 'object', properties: { id: { type: 'string' }, all: { type: 'boolean' } } } },
];

/** Tool mạng: chuyển thẳng xuống extension. */
export const NET_METHODS: Record<string, string> = {
  browser_net_log_config: 'flygo.net.logConfig',
  browser_net_log: 'flygo.net.log',
  browser_net_request: 'flygo.net.request',
  browser_net_log_clear: 'flygo.net.logClear',
  browser_net_rule_add: 'flygo.net.ruleAdd',
  browser_net_rule_set: 'flygo.net.ruleSet',
  browser_net_rule_list: 'flygo.net.ruleList',
  browser_net_rule_remove: 'flygo.net.ruleRemove',
};
