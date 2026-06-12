import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

class ParkesError():

    def __init__(self, x_trace, y_trace):
        get_trace = lambda trace: trace if type(trace) == list else pd.read_csv(trace)['CGM'].to_list()
        self.x_trace = get_trace(x_trace)
        self.y_trace = get_trace(y_trace)
        assert len(x_trace) == len(y_trace)
        self.zones = self._classify_points()

    def _above_line(self, x_1, y_1, x_2, y_2, x_gluc, y_gluc):
        if x_1 == x_2:
            return False

        y_line = ((y_1 - y_2) * x_gluc + y_2 * x_1 - y_1 * x_2) / (x_1 - x_2)
        return y_gluc > y_line

    def _below_line(self, x_1, y_1, x_2, y_2, x_gluc, y_gluc):
        return not self._above_line(x_1, y_1, x_2, y_2, x_gluc, y_gluc)

    def _classify_point(self, x_gluc, y_gluc):

        if x_gluc < 0 or x_gluc > 550 or y_gluc < 0 or y_gluc > 550:
            raise Exception(f"Invalid glucose pair: ({x_gluc}, {y_gluc}). Glucose values must be in [0, 550]")
        
        # Zone E
        if (self._above_line(0, 150, 35, 155, x_gluc, y_gluc) and 
                self._above_line(35, 155, 50, 550, x_gluc, y_gluc)):
            return 7
        
        # Zone D - left upper
        if (y_gluc > 100 and self._above_line(25, 100, 50, 125, x_gluc, y_gluc) and
                self._above_line(50, 125, 80, 215, x_gluc, y_gluc) and 
                self._above_line(80, 215, 125, 550, x_gluc, y_gluc)):
            return 6
        
        # Zone C - left upper
        if (y_gluc > 60 and self._above_line(30, 60, 50, 80, x_gluc, y_gluc) and
                self._above_line(50, 80, 70, 110, x_gluc, y_gluc) and 
                self._above_line(70, 110, 260, 550, x_gluc, y_gluc)):
            return 5
        
        # Zone B - left upper
        if (y_gluc > 50 and self._above_line(30, 50, 140, 170, x_gluc, y_gluc) and
                self._above_line(140, 170, 280, 380, x_gluc, y_gluc) and 
                (x_gluc < 280 or self._above_line(280, 380, 430, 550, x_gluc, y_gluc))):
            return 4
        
        # Zone B - right lower
        if (x_gluc > 50 and self._below_line(50, 30, 170, 145, x_gluc, y_gluc) and
                self._below_line(170, 145, 385, 300, x_gluc, y_gluc) and 
                (x_gluc < 385 or self._below_line(385, 300, 550, 450, x_gluc, y_gluc))):
            return 3
        
        # Zone C - right lower
        if (x_gluc > 120 and self._below_line(120, 30, 260, 130, x_gluc, y_gluc) and 
                self._below_line(260, 130, 550, 250, x_gluc, y_gluc)):
            return 2
        
        # Zone D - right lower
        if x_gluc > 250 and self._below_line(250, 40, 550, 150, x_gluc, y_gluc):
            return 1
        
        # Zone A
        return 0
    
    def _classify_points(self):
        return [self._classify_point(gx, gy) for gx, gy in zip(self.x_trace, self.y_trace)]
    
    def zone_count(self):
        count = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0}
        for zone in self.zones:
            count[zone] += 1
        return count
    
    def zone_indices(self):
        letter_map = {0: 'A', 1: 'D', 2: 'C', 3: 'B', 4: 'B', 5: 'C', 6: 'D', 7: 'E'}
        return [letter_map[zone] for zone in self.zones]
    
    def plot(self, title, x_axis, y_axis, size=2, save_fig_path=""):

        plt.figure(dpi=600)
        plt.clf()
        plt.title(title)
        plt.xlabel(x_axis)
        plt.ylabel(y_axis)
        plt.xlim((0, 400))
        plt.ylim((0, 400))

        e_points = [[0,150],[35,155],[50,400]]
        ud_points = [[0,100],[25,100],[50,125],[80,215],[125,400]]
        ld_points = [[250,0],[250,40],[400,150]]
        uc_points = [[0,60],[30,60],[50,80],[70,110],[260,400]]
        lc_points = [[120,0],[120,30],[260,130],[400,250]]
        ub_points = [[0,50],[30,50],[140,170],[280,380],[400,400]]
        lb_points = [[50,0],[50,30],[170,145],[385,300],[400,400]]

        for points in [e_points, ud_points, ld_points, uc_points, lc_points, ub_points, lb_points]:
            for i in range(len(points)-1):
                plt.plot(
                    [points[i][0], points[i+1][0]],
                    [points[i][1], points[i+1][1]],
                    color='black',
                    linewidth=0.8
                )
        plt.plot([0, 400], [0, 400], color='black', linewidth=0.8, ls="--")

        zone_letter_locs = [('E', 18, 366), ('D', 80, 360), ('C', 153, 348),
                            ('B', 220, 313), ('A', 248, 284), ('A', 278, 244),
                            ('B', 295, 200), ('C', 315, 124), ('D', 335, 51)]

        for label, x, y in zone_letter_locs:
            plt.text(x, y, label, color='black', fontsize=18, 
                     fontweight='bold', ha='center', va='center')
        
        colors = {'A': "#2ecc71", 'B': "#3498db", 'C': "#f39c12", 
                  'D': "#e74c3c", 'E': "#9b59b6"}
        x_trace = np.array(self.x_trace)
        y_trace = np.array(self.y_trace)
        zones = np.array(self.zones)

        for zone_name, zone_ids in [('A', [0]), ('B', [3, 4]), ('C', [2, 5]), ('D', [1, 6]), ('E', [7])]:
            mask = np.isin(zones, zone_ids)
            zone_count = np.count_nonzero(mask)
            zone_label = f"Zone {zone_name} {zone_count} ({round(100 * zone_count/len(self.zones), 2)}%)"

            plt.scatter(x_trace[mask], y_trace[mask], label=zone_label,
                        marker='o', color=colors[zone_name], s=size)
        
        plt.legend(loc="upper left", fontsize=9, markerscale=2)

        if len(save_fig_path) > 0: 
            plt.savefig(save_fig_path)

        return plt
