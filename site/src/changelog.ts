// What changed in each release, newest first. The GitHub release notes use the same words.
export const changelog = [
  {
    version: '0.1.1',
    date: '2026-10-14',
    changes: [
      '生僻字不再挡在常用词前面。比如打 yiy，第一页先给「应该」「就说」这样的常用词，两个生僻字挪到第二页开头。既不在 GB2312 也不在 Big5 里的字算作生僻字。',
      '自己造的词即使含生僻字，也照常排在前面。',
    ],
  },
  {
    version: '0.1.0',
    date: '2026-10-14',
    changes: [
      '第一个版本：五笔 86、候选位置固定、拼音反查、造词、快捷输入，以及 Developer ID 签名和公证。',
    ],
  },
];
