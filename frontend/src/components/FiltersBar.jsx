import React from "react";

export function FiltersBar({ onOpenFilters, onAutoRoute, onMapView }) {
	console.log("FiltersBar rendering");

	return (
		<div className="bg-blue-100 p-4">
			<h2 className="text-lg font-bold">Filters Bar Placeholder</h2>
			<div className="flex gap-2 mt-2">
				<button onClick={onOpenFilters} className="bg-blue-500 text-white px-4 py-2 rounded">
					Open Filters
				</button>
				<button onClick={onAutoRoute} className="bg-green-500 text-white px-4 py-2 rounded">
					Autoroute
				</button>
				<button onClick={onMapView} className="bg-purple-500 text-white px-4 py-2 rounded">
					Map View
				</button>
			</div>
		</div>
	);
}
