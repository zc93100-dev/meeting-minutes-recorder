import 'dotenv/config';
import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import os from 'os';
import { v4 as uuidv4 } from 'uuid';
import { execSync, exec } from 'child_process';

// ========== 配置 ==========
const PORT = parseInt(process.env.PORT || '19924', 10);
const SESSIONS_DIR = path.resolve(import.meta.dirname, 'sessions');
const MOARK_BASE = 'https://api.moark.com/v1';
const DEEPSEEK_BASE = 'https://api.deepseek.com';

// ========== 全局异常兜底 ==========
process.on('uncaughtException', (err) => {
  console.error('[FATAL] 未捕获异常:', err.message);
});
process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] 未处理的 Promise 拒绝:', reason);
});

// ========== Multer ==========
const upload = multer({
  dest: path.join(SESSIONS_DIR, 'temp'),
  limits: { fileSize: 200 * 1024 * 1024 },
});

// ========== App ==========
const app = express();
app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));
app.get('/health', (_req, res) => res.json({ status: 'ok', uptime: process.uptime() }));
app.use(express.static(path.resolve(import.meta.dirname, 'public')));

// ========== 工具函数 ==========

/** 确保目录存在 */
function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

/** 合并多个音频文件为一个 MP3 */
async function mergeAudioClips(clips, outputPath) {
  if (clips.length === 0) throw new Error('没有可合并的音频片段');

  const sessionDir = path.dirname(outputPath);
  const tmpDir = path.join(sessionDir, '.merge_tmp');
  ensureDir(tmpDir);

  try {
    // Step 1: 所有片段转 WAV（webm 无 duration header，必须统一格式）
    const wavFiles = [];
    for (let i = 0; i < clips.length; i++) {
      const wavPath = path.join(tmpDir, 'chunk_' + String(i).padStart(3, '0') + '.wav');
      execSync('ffmpeg -y -i "' + clips[i] + '" -c:a pcm_s16le -ar 16000 "' + wavPath + '" 2>/dev/null', { timeout: 120000 });
      wavFiles.push(wavPath);
    }

    // Step 2: concat 合并 WAV → MP3
    const listPath = path.join(tmpDir, 'concat.txt');
    const listContent = wavFiles.map(function(f) {
      return "file '" + f.replace(/'/g, "'\\\\''") + "'";
    }).join('\n');
    fs.writeFileSync(listPath, listContent);

    try {
      execSync('ffmpeg -y -f concat -safe 0 -i "' + listPath + '" -c:a libmp3lame -b:a 64k "' + outputPath + '" 2>/dev/null', { timeout: 300000 });
    } catch (e) {
      // concat 失效时用 filter_complex
      const filterParts = wavFiles.map(function(_, i) { return '[' + i + ':0]'; }).join('');
      const filterInputs = wavFiles.map(function(f) { return '-i "' + f + '"'; }).join(' ');
      execSync('ffmpeg -y ' + filterInputs + ' -filter_complex "' + filterParts + 'concat=n=' + wavFiles.length + ':v=0:a=1[out]" -map "[out]" -c:a libmp3lame -b:a 64k "' + outputPath + '" 2>/dev/null', { timeout: 300000 });
    }

    // 清理
    for (const f of wavFiles) { try { fs.unlinkSync(f); } catch {} }
    try { fs.unlinkSync(listPath); } catch {}
    try { fs.rmdirSync(tmpDir); } catch {}
  } catch (err) {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch {}
    throw new Error('合并失败: ' + err.message);
  }
}


/** 拆分音频（Moark ASR 限制 3600s）*/
async function splitAudioIfNeeded(mergedPath, sessionDir) {
  const MAX_SECONDS = 3300; // 55分钟，留余量
  const chunks = [];

  // 用 ffprobe 读时长
  let duration = 0;
  try {
    const out = execSync('ffprobe -v quiet -show_entries format=duration -of csv=p=0 "' + mergedPath + '"', { encoding: 'utf-8', timeout: 10000 }).trim();
    if (out !== 'N/A') duration = parseFloat(out);
  } catch {}
  // 如果 ffprobe 读不到（webm），用 ffmpeg 解码读
  if (duration <= 0) {
    try {
      const out = execSync('ffmpeg -i "' + mergedPath + '" -f null - 2>&1', { encoding: 'utf-8', timeout: 300000 });
      const match = out.match(/time=(\d+):(\d+):(\d+)/g);
      if (match && match.length > 0) {
        const last = match[match.length - 1];
        const parts = last.replace('time=', '').split(':');
        duration = parseInt(parts[0]) * 3600 + parseInt(parts[1]) * 60 + parseFloat(parts[2]);
      }
    } catch {}
  }

  if (duration <= MAX_SECONDS) {
    return [mergedPath];
  }

  // 需要拆分
  const numChunks = Math.ceil(duration / MAX_SECONDS);
  for (let i = 0; i < numChunks; i++) {
    const start = i * MAX_SECONDS;
    const chunkPath = path.join(sessionDir, '.asr_chunk_' + i + '.mp3');
    execSync('ffmpeg -y -i "' + mergedPath + '" -ss ' + start + ' -t ' + MAX_SECONDS + ' -c copy "' + chunkPath + '" 2>/dev/null', { timeout: 120000 });
    chunks.push(chunkPath);
  }

  return chunks;
}

/** 调用 Moark ASR */
async function moarkASR(apiKey, audioPath) {
  const formData = new FormData();
  const audioBuffer = fs.readFileSync(audioPath);
  const blob = new Blob([audioBuffer], { type: 'audio/mpeg' });
  formData.append('file', blob, path.basename(audioPath));
  formData.append('model', 'SenseVoiceSmall');
  formData.append('language', 'auto');

  const response = await fetch(`${MOARK_BASE}/audio/transcriptions`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}` },
    body: formData,
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw new Error(err.error?.message || `ASR 失败 (${response.status})`);
  }
  return response.json();
}

/** 调用 DeepSeek 生成会议纪要 */
async function generateMeetingMinutes(transcript, apiKey) {
  const prompt = `你是一位专业的会议记录员。请根据以下会议录音转写内容，生成一份结构清晰、重点突出的会议纪要。

## 要求：
1. 使用中文输出
2. 包含以下部分（如果内容缺失某部分则跳过）：
   - 📋 **会议概要**：会议主题、时间（若有提及）、参会人（若有提及）
   - 🎯 **核心议题**：逐条列出讨论的主要议题
   - 💡 **关键讨论**：每个议题的讨论要点、不同观点、决策依据
   - ✅ **决议与结论**：会议达成的共识和结论
   - 📝 **待办事项**：明确的责任人、任务内容和截止时间（若提及）
3. 转写内容可能因口音或环境噪音有识别错误，请根据上下文合理推断修正
4. 如果内容明显是闲聊或不完整，如实说明
5. 用 Markdown 格式输出，层级清晰但不要过于冗长

## 会议录音转写内容：
${transcript}`;

  const response = await fetch(`${DEEPSEEK_BASE}/v1/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: 'deepseek-v4-flash',
      messages: [
        { role: 'system', content: '你是一位专业的会议记录员，擅长从冗长的会议录音中提取关键信息并生成结构化纪要。回复简洁专业，使用 Markdown 格式。' },
        { role: 'user', content: prompt },
      ],
      max_tokens: 8192,
      temperature: 0.3,
    }),
  });

  if (!response.ok) {
    const err = await response.text().catch(() => '');
    throw new Error(`DeepSeek 调用失败 (${response.status}): ${err}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content || '（未能生成会议纪要）';
}

// ========== API 路由 ==========

/** 
 * POST /api/upload
 * 上传一个音频片段，返回片段 ID
 */
app.post('/api/upload', upload.single('audio'), (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: '未提供音频文件' });
    const sessionId = req.body.sessionId || uuidv4();
    const sessionDir = path.join(SESSIONS_DIR, sessionId);
    ensureDir(sessionDir);

    const clipId = uuidv4().slice(0, 8);
    const ext = path.extname(req.file.originalname) || '.webm';
    const destPath = path.join(sessionDir, `clip_${clipId}${ext}`);
    fs.renameSync(req.file.path, destPath);

    // 保存时长元数据
    const duration = parseFloat(req.body.duration) || 0;
    const metaPath = path.join(sessionDir, 'metadata.json');
    let metadata = [];
    if (fs.existsSync(metaPath)) {
      try { metadata = JSON.parse(fs.readFileSync(metaPath, 'utf-8')); } catch {}
    }
    metadata.push({ clipId, file: `clip_${clipId}${ext}`, size: req.file.size, duration });
    fs.writeFileSync(metaPath, JSON.stringify(metadata, null, 2));

    const totalDuration = metadata.reduce((s, c) => s + (c.duration || 0), 0);

    res.json({
      success: true,
      sessionId,
      clipId,
      duration,
      totalDuration,
      clipPath: `clip_${clipId}${ext}`,
      totalClips: metadata.length,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/clips/:sessionId
 * 获取某个会话的所有音频片段
 */
app.get('/api/clips/:sessionId', (req, res) => {
  try {
    const sessionDir = path.join(SESSIONS_DIR, req.params.sessionId);
    if (!fs.existsSync(sessionDir)) return res.json({ clips: [] });
    const files = fs.readdirSync(sessionDir)
      .filter(f => f.startsWith('clip_'))
      .sort();
    res.json({ clips: files.map((f, i) => ({ name: f, index: i + 1 })) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * GET /api/metadata/:sessionId
 * 获取片段元数据（含实际时长）
 * 优先用 ffprobe 读取真实时长，兜底用文件大小估算
 */
app.get('/api/metadata/:sessionId', (req, res) => {
  try {
    const sessionDir = path.join(SESSIONS_DIR, req.params.sessionId);
    if (!fs.existsSync(sessionDir)) return res.json({ clips: [], totalDuration: 0 });

    const metaPath = path.join(sessionDir, 'metadata.json');
    let metadata = [];
    if (fs.existsSync(metaPath)) {
      try { metadata = JSON.parse(fs.readFileSync(metaPath, 'utf-8')); } catch {}
    }

    const clips = fs.readdirSync(sessionDir)
      .filter(f => f.startsWith('clip_'))
      .sort();

    // 用 ffprobe 获取每段的真实时长
    const results = clips.map((f, i) => {
      const filePath = path.join(sessionDir, f);
      let duration = 0;

      // 优先从 metadata.json 读
      const metaEntry = metadata.find(m => m.file === f);
      if (metaEntry && metaEntry.duration > 0) {
        duration = metaEntry.duration;
      }

      // 否则用 ffprobe
      if (duration <= 0) {
        try {
          const probeOut = execSync(
            `ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${filePath}"`,
            { encoding: 'utf-8', timeout: 5000 }
          ).trim();
          duration = parseFloat(probeOut) || 0;
        } catch {}
      }

      // 兜底：文件大小估算
      if (duration <= 0) {
        const stats = fs.statSync(filePath);
        duration = stats.size / 16000; // ~128kbps with overhead
      }

      return { name: f, index: i + 1, duration: Math.round(duration), size: fs.statSync(filePath).size };
    });

    const totalDuration = results.reduce((s, c) => s + c.duration, 0);

    res.json({ clips: results, totalDuration });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * DELETE /api/clips/:sessionId
 * 清空会话
 */
app.delete('/api/clips/:sessionId', (req, res) => {
  try {
    const sessionDir = path.join(SESSIONS_DIR, req.params.sessionId);
    if (fs.existsSync(sessionDir)) {
      fs.rmSync(sessionDir, { recursive: true, force: true });
    }
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/process
 * 处理所有音频片段 → 合并 → ASR → 会议纪要
 */
app.post('/api/process', async (req, res) => {
  try {
    const { sessionId, moarkApiKey, deepseekApiKey } = req.body;
    if (!sessionId) return res.status(400).json({ error: '请提供 sessionId' });
    if (!moarkApiKey) return res.status(400).json({ error: '请提供模力方舟 API Key（用于语音识别）' });

    const sessionDir = path.join(SESSIONS_DIR, sessionId);
    if (!fs.existsSync(sessionDir)) return res.status(400).json({ error: '会话不存在' });

    const clips = fs.readdirSync(sessionDir)
      .filter(f => f.startsWith('clip_'))
      .sort()
      .map(f => path.join(sessionDir, f));

    if (clips.length === 0) return res.status(400).json({ error: '没有音频片段' });

    // 1. 报告进度：合并中
    res.write(JSON.stringify({ step: 'merge', message: `正在合并 ${clips.length} 个音频片段...` }) + '\n');

    const mergedPath = path.join(sessionDir, 'merged.mp3');
    await mergeAudioClips(clips, mergedPath);

    // 2. 如果音频超过3600s，自动拆分
    const audioChunks = await splitAudioIfNeeded(mergedPath, sessionDir);

    // 3. 报告进度：语音识别
    res.write(JSON.stringify({ step: 'asr', message: '正在进行语音识别（ASR）' + (audioChunks.length > 1 ? '，共 ' + audioChunks.length + ' 段' : '') + '...' }) + '\n');

    // 逐段 ASR
    let transcript = '';
    for (let i = 0; i < audioChunks.length; i++) {
      if (audioChunks.length > 1) {
        res.write(JSON.stringify({ step: 'asr', message: '语音识别第 ' + (i+1) + '/' + audioChunks.length + ' 段...' }) + '\n');
      }
      const asrResult = await moarkASR(moarkApiKey, audioChunks[i]);
      transcript += (asrResult.text || '') + '\n';
      // 清理临时 chunk
      if (audioChunks[i] !== mergedPath) {
        try { fs.unlinkSync(audioChunks[i]); } catch {}
      }
    }
    transcript = transcript.trim();
    if (!transcript) throw new Error('ASR 未能识别到文字内容');

    // 4. 报告进度：生成纪要
    res.write(JSON.stringify({
      step: 'summary',
      message: '正在生成会议纪要...',
      transcript,
    }) + '\n');

    // 5. 生成会议纪要
    const minutes = await generateMeetingMinutes(
      transcript,
      deepseekApiKey || process.env.DEEPSEEK_API_KEY
    );

    // 5. 保存纪要
    const minutesPath = path.join(sessionDir, 'meeting-minutes.md');
    fs.writeFileSync(minutesPath, minutes, 'utf-8');

    // 6. 输出到桌面
    const desktopPath = exportToDesktop(sessionDir, transcript, minutes);

    // 7. 返回结果
    res.write(JSON.stringify({
      step: 'done',
      message: '完成！',
      transcript,
      minutes,
      clipCount: clips.length,
      sessionId,
      desktopPath,
    }) + '\n');
    res.end();
  } catch (err) {
    res.write(JSON.stringify({ step: 'error', message: err.message }) + '\n');
    res.end();
  }
});

/**
 * GET /api/load-keys
 * 返回已保存的 API Key（前端自动填入）
 */
app.get('/api/load-keys', (_req, res) => {
  res.json({
    moarkKey: process.env.MOARK_API_KEY || '',
    deepseekKey: process.env.DEEPSEEK_API_KEY || '',
  });
});

/**
 * POST /api/save-key
 * 保存 API Key 到 .env
 */
app.post('/api/save-key', (req, res) => {
  try {
    const { moarkApiKey, deepseekApiKey } = req.body;
    const envPath = path.resolve(import.meta.dirname, '.env');
    let envContent = '';
    if (fs.existsSync(envPath)) {
      envContent = fs.readFileSync(envPath, 'utf-8');
    }

    if (moarkApiKey) {
      // Update or add
      if (envContent.match(/^MOARK_API_KEY=/m)) {
        envContent = envContent.replace(/^MOARK_API_KEY=.*$/m, `MOARK_API_KEY=${moarkApiKey}`);
      } else {
        envContent += `\nMOARK_API_KEY=${moarkApiKey}`;
      }
    }
    if (deepseekApiKey) {
      if (envContent.match(/^DEEPSEEK_API_KEY=/m)) {
        envContent = envContent.replace(/^DEEPSEEK_API_KEY=.*$/m, `DEEPSEEK_API_KEY=${deepseekApiKey}`);
      } else {
        envContent += `\nDEEPSEEK_API_KEY=${deepseekApiKey}`;
      }
    }

    // Also update the process env for current session
    if (moarkApiKey) process.env.MOARK_API_KEY = moarkApiKey;
    if (deepseekApiKey) process.env.DEEPSEEK_API_KEY = deepseekApiKey;

    fs.writeFileSync(envPath, envContent.trim() + '\n');
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ========== 输出到桌面 ==========

/** 简易 MD→HTML 转 DOCX（纯文本 docx 靠 AppleScript） */
function mdToDocx(mdContent, outputPath) {
  // 用 textutil 转成 docx（macOS 内置，支持 .md）
  const tmpMd = outputPath.replace(/\.docx$/, '_tmp.md');
  fs.writeFileSync(tmpMd, mdContent, 'utf-8');
  try {
    execSync(`textutil -convert docx -output "${outputPath}" "${tmpMd}" 2>/dev/null`, { timeout: 30000 });
  } catch {}
  try { fs.unlinkSync(tmpMd); } catch {}
}

/** 从会议纪要中提取主题作为文件名 */
function extractTitle(mdContent) {
  // 找第一个 # 或 ## 或 ### 标题
  const match = mdContent.match(/^#{1,3}\s+(.+)$/m);
  if (match) {
    // 去掉 emoji 和特殊字符，截取前 30 字
    let title = match[1]
      .replace(/\*\*/g, '')
      .replace(/[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/gu, '').trim();
    if (title.length > 30) title = title.slice(0, 30);
    // 去掉文件名非法字符
    title = title.replace(/[\/:*?"<>|]/g, '').trim();
    return title || '会议纪要';
  }
  return '会议纪要';
}

/** 导出录音和纪要到桌面 */
function exportToDesktop(sessionDir, transcript, minutes) {
  const desktopDir = path.join(os.homedir(), 'Desktop', '会议纪要');
  ensureDir(desktopDir);

  // 当前时间作为文件夹名（录音结束时间）
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const folderName = `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())} (会议纪要)`;
  const destDir = path.join(desktopDir, folderName);
  ensureDir(destDir);

  try {
    // 只复制合并后的完整 MP3
    const mergedSrc = path.join(sessionDir, 'merged.mp3');
    if (fs.existsSync(mergedSrc)) {
      fs.copyFileSync(mergedSrc, path.join(destDir, 'merged.mp3'));
    }

    // 生成 docx（以会议主题命名）
    const docxName = extractTitle(minutes) + '.docx';
    const docxPath = path.join(destDir, docxName);
    mdToDocx(minutes, docxPath);

    console.log(`[export] 已导出到: ${destDir}`);
    console.log(`[export] 文件: merged.mp3, ${docxName}`);
  } catch (err) {
    console.error('[export] 导出失败:', err.message);
  }

  return destDir;
}

// ========== 启动 ==========
ensureDir(SESSIONS_DIR);
ensureDir(path.join(SESSIONS_DIR, 'temp'));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`
╔══════════════════════════════════════════╗
║     🎙️ 会议纪要录音器 - 服务已启动      ║
║──────────────────────────────────────────║
║  地址: http://localhost:${PORT}                   ║
║  录音 → 合并 → ASR → AI 纪要            ║
╚══════════════════════════════════════════╝
  `);
});
