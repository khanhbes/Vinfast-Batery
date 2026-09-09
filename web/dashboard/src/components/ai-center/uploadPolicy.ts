export function validateModelUpload(file: { name: string; size: number } | null, version: string): string | null {
  if (!file) return 'Select a model file before uploading.';
  if (!/\.(onnx|tflite)$/i.test(file.name)) return 'Only ONNX or TFLite models can be uploaded through the web portal.';
  if (file.size <= 0 || file.size > 64 * 1024 * 1024) return 'The file must not be empty or exceed 64 MiB.';
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(version.trim())) return 'Version must contain 1–128 letters, numbers, dots, hyphens or underscores.';
  return null;
}
