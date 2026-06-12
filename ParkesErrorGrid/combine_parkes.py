from ParkesErrorGrid.parkes_error import ParkesError
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.image as mpimg

users = ['child005', 'child002', 'adolescent007', 'adolescent009', 'child003', 'child004', 'adolescent008', 'adolescent006', 'adolescent001', 'adult006', 'adult001', 'adult008', 'child010', 'adult009', 'adult007', 'adolescent004', 'adolescent003', 'adult010', 'child008', 'child001', 'child006', 'adolescent002', 'adolescent005', 'child007', 'child009', 'adult002', 'adult005', 'adolescent010', 'adult004', 'adult003']

child_traces_f = []
adolescent_traces_f = []
adult_traces_f = []
child_traces_b = []
adolescent_traces_b = []
adult_traces_b = []

for user in users:
    if user[:5] == "child":
        child_traces_f += pd.read_csv(f"simglucoseResults/{user}/fixed_hourScen.csv")["CGM"].to_list()
        child_traces_b += pd.read_csv(f"simglucoseResults/{user}/jsbug_hourScen.csv")["CGM"].to_list()
    elif user[:10] == "adolescent":
        adolescent_traces_f += pd.read_csv(f"simglucoseResults/{user}/fixed_hourScen.csv")["CGM"].to_list()
        adolescent_traces_b += pd.read_csv(f"simglucoseResults/{user}/jsbug_hourScen.csv")["CGM"].to_list()
    else:
        adult_traces_f += pd.read_csv(f"simglucoseResults/{user}/fixed_hourScen.csv")["CGM"].to_list()
        adult_traces_b += pd.read_csv(f"simglucoseResults/{user}/jsbug_hourScen.csv")["CGM"].to_list()


pe_c = ParkesError(child_traces_f, child_traces_b)
pe_c.plot(f"simglucose Children Virtual Patients", f"Swift Algorithm Glucose", f"Original Javascript Algorithm Glucose", size=1, save_fig_path="simglucoseResults/ChildrenParkeError.png")

pe_ado = ParkesError(adolescent_traces_f, adolescent_traces_b)
pe_ado.plot(f"simglucose Adolescent Virtual Patients", f"Swift Algorithm Glucose", f"Original Javascript Algorithm Glucose", size=1, save_fig_path="simglucoseResults/AdolescentParkeError.png")

pe_adu = ParkesError(adult_traces_f, adult_traces_b)
pe_adu.plot(f"simglucose Adult Virtual Patients", f"Swift Algorithm Glucose", f"Original Javascript Algorithm Glucose", size=1, save_fig_path="simglucoseResults/AdultParkeError.png")

pe_c_2 = ParkesError(child_traces_b, child_traces_f)
pe_c_2.plot(f"simglucose Children Virtual Patients", f"Original Javascript Algorithm Glucose",f"Swift Algorithm Glucose", size=1, save_fig_path="simglucoseResults/ChildrenParkeError_flipped.png")

pe_ado_2 = ParkesError(adolescent_traces_b, adolescent_traces_f)
pe_ado_2.plot(f"simglucose Adolescent Virtual Patients", f"Original Javascript Algorithm Glucose", f"Swift Algorithm Glucose", size=1, save_fig_path="simglucoseResults/AdolescentParkeError_flipped.png")

pe_adu_2 = ParkesError(adult_traces_b, adult_traces_f)
pe_adu_2.plot(f"simglucose Adult Virtual Patients", f"Original Javascript Algorithm Glucose", f"Swift Algorithm Glucose", size=1, save_fig_path="simglucoseResults/AdultParkeError_flipped.png")

files = [
    "simglucoseResults/AdultParkeError.png", "simglucoseResults/AdultParkeError_flipped.png",
    "simglucoseResults/AdolescentParkeError.png", "simglucoseResults/AdolescentParkeError_flipped.png",
    "simglucoseResults/ChildrenParkeError.png", "simglucoseResults/ChildrenParkeError_flipped.png",
]

fig, axes = plt.subplots(3, 2, figsize=(10, 12))

for ax, file in zip(axes.flat, files):
    img = mpimg.imread(file)
    ax.imshow(img)
    ax.axis("off")
    ax.set_position([0, 0, 1, 1])

plt.subplots_adjust(wspace=0, hspace=0)
plt.savefig("simglucoseResults/combined.png", dpi=300, bbox_inches="tight", pad_inches=0)