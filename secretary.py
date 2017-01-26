import numpy as np
import pandas as pd
import math

sample = 100
trials = 1000
saved_trials = pd.DataFrame()


for m in range(trials):
    df = pd.DataFrame(np.arange(1,101), columns=['Rating'])
    df = df.sample(frac=1).reset_index(drop=True)
    n = round(len(df)/math.e)
    min_rating = df.loc[df.index <= n, 'Rating'].max()
    
    #need to find the first candidate after n with a rating > min_rating
    k = n+1
    while True:
        if k == df.index.max():
            saved_trials = saved_trials.append(df.loc[df.index.max()])
            break
        elif df['Rating'][k] > min_rating:
            saved_trials = saved_trials.append(df.loc[k])
            break
        elif df['Rating'][k] <= min_rating:
            k = k+1

saved_trials = saved_trials.reset_index()

          
len(saved_trials[saved_trials['Rating']==sample])/len(saved_trials)
