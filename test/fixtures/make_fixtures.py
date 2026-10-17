# -*- coding: utf-8 -*-
"""Generate the sanitized fixtures committed to git.

Real exports live in test/fixtures/local/ (gitignored). These samples reproduce
every structural quirk we rely on: UTF-8 BOM, LF newlines, two spaces around
the time value, comma-separated tags and attachments, an empty note, a transfer
row, and two rows sharing one attachment file.
"""
import csv, io, os

OUT = os.path.dirname(os.path.abspath(__file__))

HEADER_ZH = ['类型', '分类', '二级分类', '金额', '币种', '账户', '转出账户', '转入账户',
             '备注', '时间', '标签', '附件']
HEADER_EN = ['Type', 'Category', 'Subcategory', 'Amount', 'Currency', 'Account',
             'From Account', 'To Account', 'Note', 'Time', 'Tags', 'Attachments']

ROWS = [
    ['支出', '餐饮', '', '30.02', 'CNY', '现金', '', '', '街角炸鸡', '  2026-10-17 19:27:00  ', '图片记账,AI记账', 'sha_aaaa1111.jpg'],
    ['支出', '交通', '', '12.00', 'CNY', '现金', '', '', '地铁', '  2026-10-17 08:05:00  ', '通勤', ''],
    ['支出', '购物', '', '24.88', 'CNY', '储蓄卡', '', '', '衣架', '  2026-10-16 21:48:00  ', '图片记账,AI记账', 'sha_bbbb2222.jpg'],
    ['支出', '餐饮', '', '12.00', 'CNY', '储蓄卡', '', '', '', '  2026-10-16 18:39:52  ', '图片记账,AI记账', 'sha_cccc3333.jpg'],
    ['收入', '工资', '', '14519.01', 'CNY', '储蓄卡', '', '', '九月工资', '  2026-10-15 13:58:51  ', '', ''],
    # 同一时刻、不同金额、共用一张图：验证去重键与一对多附件
    ['支出', '购物', '', '69.00', 'CNY', '现金', '', '', '混合坚果', '  2026-10-14 15:53:00  ', '图片记账', 'sha_dddd4444.jpg'],
    ['支出', '购物', '', '130.50', 'CNY', '现金', '', '', '零食组合', '  2026-10-14 15:53:00  ', '图片记账', 'sha_dddd4444.jpg'],
    ['支出', '餐饮', '', '38.50', 'CNY', '现金', '', '', '聚餐', '  2026-10-13 12:30:00  ', '', ''],
    # 转账：导入时应跳过
    ['转账', '', '', '500.00', 'CNY', '', '储蓄卡', '信用卡', '还信用卡', '  2026-10-12 09:00:00  ', '', ''],
    ['支出', '交通', '', '8.00', 'CNY', '信用卡', '', '', '公交', '  2026-10-11 07:40:00  ', '', ''],
]

EN_ROWS = [
    ['Expense', 'Food', '', '30.02', 'CNY', 'Cash', '', '', 'Fried chicken', '  2026-10-17 19:27:00  ', 'photo,ai', 'sha_aaaa1111.jpg'],
    ['Income', 'Salary', '', '14519.01', 'CNY', 'Bank Card', '', '', 'September pay', '  2026-10-15 13:58:51  ', '', ''],
    ['Transfer', '', '', '500.00', 'CNY', '', 'Bank Card', 'Credit Card', 'Repay', '  2026-10-12 09:00:00  ', '', ''],
]


def build(path, header, rows):
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(header)
    w.writerows(rows)
    data = buf.getvalue().replace('\r\n', '\n')
    with open(path, 'wb') as f:
        f.write(b'\xef\xbb\xbf' + data.encode('utf-8'))
    print('wrote', path, len(rows), 'rows')


build(os.path.join(OUT, 'beecount_sample.csv'), HEADER_ZH, ROWS)
build(os.path.join(OUT, 'beecount_sample_en.csv'), HEADER_EN, EN_ROWS)
