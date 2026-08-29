import { ModelTypeMeta, ModelAccent } from '../types';
import DynamicInput from './DynamicInput';

interface Props {
  meta: ModelTypeMeta;
  inputState: Record<string, any>;
  onChange: (field: string, value: any) => void;
  accent: ModelAccent;
  disabled?: boolean;
}

export default function ModelInputPanel({
  meta,
  inputState,
  onChange,
  accent,
  disabled = false,
}: Props) {
  const displayFields = meta.visibleInputFields && meta.visibleInputFields.length > 0
    ? meta.visibleInputFields
    : meta.inputFields || [];

  const schema = meta.inputSchema || {};

  return (
    <div className="mt-6 grid gap-x-6 gap-y-5 sm:grid-cols-2">
      {displayFields.map((field) => (
        <DynamicInput
          key={field}
          fieldName={field}
          schema={schema[field]}
          value={inputState[field]}
          onChange={(val) => onChange(field, val)}
          accent={accent}
          disabled={disabled}
        />
      ))}
    </div>
  );
}
