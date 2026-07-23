import csv
import itertools
from datetime import datetime
import matplotlib.pyplot as plt
import matplotlib.dates as mdates

def read_csv(path):
    times, glucose, autosens, sens_ratio, insulin = [], [], [], [], []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = datetime.fromisoformat(row['time'])
            times.append(t)
            glucose.append(float(row['glucose']))
            ar = row.get('autosens ratio', '')
            autosens.append(float(ar) if ar else None)
            sr = row.get('sensitivityRatio', '')
            sens_ratio.append(float(sr) if sr else None)
            insulin.append(float(row['insulin']))
    return times, glucose, autosens, sens_ratio, insulin

fixed_t, fixed_g, fixed_as, fixed_sr, fixed_ins = read_csv('autosensBugInvoke/simOut_DynamicISF_ON/fixed/14CFC51D-9B72-4B05-93BC-3544FCA8D58B_2025-11-02T10:15:00Z_output.csv')
buggy_t, buggy_g, buggy_as, buggy_sr, buggy_ins = read_csv('autosensBugInvoke/simOut_DynamicISF_ON/buggy/14CFC51D-9B72-4B05-93BC-3544FCA8D58B_2025-11-02T10:15:00Z_output.csv')

fixed_cum = list(itertools.accumulate(fixed_ins))
buggy_cum = list(itertools.accumulate(buggy_ins))

fig, (ax, ax3, ax4, ax2) = plt.subplots(4, 1, figsize=(14, 11), height_ratios=[3, 1, 1, 1], sharex=True)

# Highlight in-range zone (70-180 mg/dL)
ax.axhspan(70, 180, color='#2ecc71', alpha=0.12, label='In range (70-180)')
ax.axhline(70, color='#2ecc71', linewidth=0.8, linestyle='--', alpha=0.5)
ax.axhline(180, color='#2ecc71', linewidth=0.8, linestyle='--', alpha=0.5)

ax.plot(fixed_t, fixed_g, label='Fixed', linewidth=1.5)
ax.plot(buggy_t, buggy_g, label='Buggy', linewidth=1.5, alpha=0.8)

ax.set_ylabel('Glucose (mg/dL)')
ax.set_title('Glucose Traces: Fixed vs Buggy')
ax.legend()
ax.grid(True, alpha=0.3)

# Insulin subplot
ax3.plot(fixed_t, fixed_ins, label='Fixed', linewidth=1.5)
ax3.plot(buggy_t, buggy_ins, label='Buggy', linewidth=1.5, alpha=0.8)
ax3.set_ylabel('Insulin (U)')
ax3.legend()
ax3.grid(True, alpha=0.3)

# Cumulative insulin subplot
ax4.plot(fixed_t, fixed_cum, label='Fixed', linewidth=1.5)
ax4.plot(buggy_t, buggy_cum, label='Buggy', linewidth=1.5, alpha=0.8)
ax4.set_ylabel('Cumulative\nInsulin (U)')
ax4.legend()
ax4.grid(True, alpha=0.3)

# Autosens ratio subplot
ax2.plot(fixed_t, fixed_as, label='Fixed autosens', linewidth=1.5, color='C0')
ax2.plot(buggy_t, buggy_as, label='Buggy autosens', linewidth=1.5, color='C1', alpha=0.8)
ax2.plot(fixed_t, fixed_sr, label='Fixed sensitivityRatio', linewidth=1.0, color='C0', linestyle='--', alpha=0.6)
ax2.plot(buggy_t, buggy_sr, label='Buggy sensitivityRatio', linewidth=1.0, color='C1', linestyle='--', alpha=0.6)
ax2.axhline(1.0, color='gray', linewidth=0.8, linestyle='--', alpha=0.5)
ax2.set_xlabel('Time')
ax2.set_ylabel('Autosens Ratio')
ax2.legend(fontsize=8)
ax2.grid(True, alpha=0.3)

ax2.xaxis.set_major_formatter(mdates.DateFormatter('%H:%M'))
ax2.xaxis.set_major_locator(mdates.HourLocator(interval=2))
fig.autofmt_xdate()

plt.tight_layout()
plt.savefig('glucose_plot.png', dpi=150)
print('Saved glucose_plot.png')
