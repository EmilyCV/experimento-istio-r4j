import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const RPS = parseInt(__ENV.RPS || '50');
const DURATION = __ENV.DURATION || '3m';
const WARMUP = __ENV.WARMUP || '1m';

const successRate = new Rate('success_rate');
const errorsByCode = new Counter('errors_by_code');

export const options = {
  scenarios: {
    load: {
      executor: 'constant-arrival-rate',
      rate: RPS,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: Math.min(RPS * 2, 100),
      maxVUs: Math.min(RPS * 4, 200),
    },
  },
  thresholds: {},
};

export function setup() {
  console.log(`Target: ${BASE_URL}/api/order/1`);
  console.log(`Rate: ${RPS} RPS, Duration: ${DURATION}, Warmup: ${WARMUP}`);

  // Warmup phase
  const warmupDuration = parseDuration(WARMUP);
  if (warmupDuration > 0) {
    console.log(`Warming up for ${WARMUP}...`);
    const end = Date.now() + warmupDuration;
    while (Date.now() < end) {
      http.get(`${BASE_URL}/api/order/1`);
      sleep(0.1);
    }
    console.log('Warmup complete.');
  }
}

export default function () {
  const id = Math.floor(Math.random() * 1000) + 1;
  const res = http.get(`${BASE_URL}/api/order/${id}`, {
    tags: { name: 'GET /api/order/{id}' },
  });

  const isSuccess = res.status >= 200 && res.status < 300;
  successRate.add(isSuccess);

  if (!isSuccess) {
    errorsByCode.add(1, { status: String(res.status) });
  }

  check(res, {
    'status is 2xx': (r) => r.status >= 200 && r.status < 300,
  });
}

export function handleSummary(data) {
  const outputPath = __ENV.OUTPUT_PATH || './results.json';
  return {
    [outputPath]: JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ' }),
  };
}

function textSummary(data, opts) {
  const indent = (opts && opts.indent) || '';
  const metrics = data.metrics;
  let out = '\n=== Summary ===\n';
  if (metrics.http_req_duration) {
    const d = metrics.http_req_duration.values;
    out += `${indent}http_req_duration:\n`;
    out += `${indent}  p50=${d.med?.toFixed(2)}ms p90=${d['p(90)']?.toFixed(2)}ms p95=${d['p(95)']?.toFixed(2)}ms p99=${d['p(99)']?.toFixed(2)}ms max=${d.max?.toFixed(2)}ms\n`;
  }
  if (metrics.http_reqs) {
    out += `${indent}http_reqs: ${metrics.http_reqs.values.count} (${metrics.http_reqs.values.rate?.toFixed(2)}/s)\n`;
  }
  if (metrics.success_rate) {
    out += `${indent}success_rate: ${(metrics.success_rate.values.rate * 100).toFixed(2)}%\n`;
  }
  return out;
}

function parseDuration(s) {
  const match = s.match(/^(\d+)(s|m|h)$/);
  if (!match) return 0;
  const val = parseInt(match[1]);
  switch (match[2]) {
    case 's': return val * 1000;
    case 'm': return val * 60000;
    case 'h': return val * 3600000;
    default: return 0;
  }
}
