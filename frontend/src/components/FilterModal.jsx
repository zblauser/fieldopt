import React from "react";

export function FilterModal({
	isOpen,
	onClose,
	regions,
	jobTypes,
	techs,
	selectedRegions,
	selectedJobTypes,
	selectedTechs,
	setSelectedRegions,
	setSelectedJobTypes,
	setSelectedTechs,
}) {
	if (!isOpen) return null;

	const toggle = (item, list, setList) => {
		setList((prev) =>
			prev.includes(item)
				? prev.filter((i) => i !== item)
				: [...prev, item]
		);
	};

	const makeList = (label, items, selected, setSelected) => (
		<div>
			<h4 className="font-semibold mb-1">{label}</h4>
			<div className="flex flex-wrap gap-2">
				{items.map((item) => (
					<button
						key={item}
						onClick={() => toggle(item, selected, setSelected)}
						className={`px-2 py-1 border rounded ${
							selected.includes(item) ? "bg-blue-600 text-white" : "bg-white"
						}`}
					>
						{item}
					</button>
				))}
			</div>
		</div>
	);

	return (
		<div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
			<div className="bg-white p-6 rounded shadow-md w-[600px] max-h-[80vh] overflow-y-auto space-y-4">
				<h3 className="text-xl font-bold">Filters</h3>
				{makeList("Regions", regions, selectedRegions, setSelectedRegions)}
				{makeList("Job Types", jobTypes, selectedJobTypes, setSelectedJobTypes)}
				{makeList(
					"Technicians",
					techs.map((t) => t.name),
					selectedTechs,
					setSelectedTechs
				)}
				<div className="text-right">
					<button onClick={onClose} className="px-4 py-2 bg-gray-800 text-white rounded">
						Close
					</button>
				</div>
			</div>
		</div>
	);
}
