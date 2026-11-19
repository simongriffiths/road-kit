import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';

// One choice from a few, as buttons that report whether they are pressed.
export function SegmentedControl<T extends string>({ label, value, options, onChange }: {
  label: string;
  value: T;
  options: { value: T; label: string }[];
  onChange: (value: T) => void;
}) {
  return (
    <ToggleGroup
      aria-label={label}
      className="rounded-lg bg-secondary p-0.5"
      onValueChange={(v) => { if (v.length > 0) onChange(v[0] as T); }}
      value={[value]}
    >
      {options.map((o) => (
        <ToggleGroupItem className="min-h-8 px-3.5 text-[13px] data-[pressed]:bg-card data-[pressed]:font-semibold data-[pressed]:shadow-sm" key={o.value} value={o.value}>
          {o.label}
        </ToggleGroupItem>
      ))}
    </ToggleGroup>
  );
}
